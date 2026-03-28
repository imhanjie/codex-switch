import Foundation

public struct AuthParser: Sendable {
    public init() {}

    public func parseAuthFile(at url: URL) throws -> (AuthInfo, Data) {
        do {
            let data = try Data(contentsOf: url)
            return try parseAuthData(data)
        } catch CocoaError.fileReadNoSuchFile {
            throw CodexSwitchError("未找到认证文件：\(url.path)")
        } catch let error as CodexSwitchError {
            throw error
        } catch {
            throw CodexSwitchError("无法读取认证文件：\(error.localizedDescription)")
        }
    }

    public func parseAuthData(_ rawData: Data) throws -> (AuthInfo, Data) {
        let payload: [String: Any]
        do {
            let object = try JSONSerialization.jsonObject(with: rawData)
            guard let dictionary = object as? [String: Any] else {
                throw CodexSwitchError("auth.json 不是合法的 JSON")
            }
            payload = dictionary
        } catch let error as CodexSwitchError {
            throw error
        } catch {
            throw CodexSwitchError("auth.json 不是合法的 JSON")
        }

        if payload["OPENAI_API_KEY"] is String || payload["OPENAI_API_KEY"] is NSNumber {
            throw CodexSwitchError("当前只支持 ChatGPT 登录态，不支持 API Key 模式")
        }

        let authMode = try requireNonEmptyString(payload["auth_mode"], fieldName: "auth_mode")
        guard authMode == "chatgpt" else {
            throw CodexSwitchError("当前只支持 auth_mode=chatgpt 的认证文件")
        }

        guard let tokens = payload["tokens"] as? [String: Any] else {
            throw CodexSwitchError("auth.json 缺少 tokens 字段")
        }

        let accessToken = try requireNonEmptyString(tokens["access_token"], fieldName: "tokens.access_token")
        let refreshToken = try requireNonEmptyString(tokens["refresh_token"], fieldName: "tokens.refresh_token")
        let tokenAccountID = try requireNonEmptyString(tokens["account_id"], fieldName: "tokens.account_id")
        let idToken = try requireNonEmptyString(tokens["id_token"], fieldName: "tokens.id_token")

        let claims = try decodeJWTPayload(idToken)
        let email = try requireNonEmptyString(claims["email"], fieldName: "email").lowercased()

        guard let authClaim = claims["https://api.openai.com/auth"] as? [String: Any] else {
            throw CodexSwitchError("JWT 中缺少 https://api.openai.com/auth 声明")
        }

        let jwtAccountID = try requireNonEmptyString(
            authClaim["chatgpt_account_id"],
            fieldName: "chatgpt_account_id"
        )
        guard jwtAccountID == tokenAccountID else {
            throw CodexSwitchError("tokens.account_id 与 JWT 中的 chatgpt_account_id 不一致")
        }

        let chatgptUserID = try requireNonEmptyString(
            authClaim["chatgpt_user_id"] ?? authClaim["user_id"],
            fieldName: "chatgpt_user_id"
        )
        let plan = optionalString(authClaim["chatgpt_plan_type"])
        let recordKey = "\(chatgptUserID)::\(tokenAccountID)"

        return (
            AuthInfo(
                email: email,
                chatgptUserID: chatgptUserID,
                chatgptAccountID: tokenAccountID,
                recordKey: recordKey,
                accessToken: accessToken,
                refreshToken: refreshToken,
                plan: plan,
                authMode: authMode
            ),
            rawData
        )
    }

    private func decodeJWTPayload(_ token: String) throws -> [String: Any] {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            throw CodexSwitchError("tokens.id_token 不是合法的 JWT")
        }

        let payloadData = try Base64URL.decode(String(parts[1]))
        do {
            let object = try JSONSerialization.jsonObject(with: payloadData)
            guard let dictionary = object as? [String: Any] else {
                throw CodexSwitchError("JWT payload 不是对象")
            }
            return dictionary
        } catch let error as CodexSwitchError {
            throw error
        } catch {
            throw CodexSwitchError("无法解析 JWT payload")
        }
    }

    private func requireNonEmptyString(_ value: Any?, fieldName: String) throws -> String {
        guard let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CodexSwitchError("auth.json 缺少或包含空字段：\(fieldName)")
        }
        return string
    }

    private func optionalString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
