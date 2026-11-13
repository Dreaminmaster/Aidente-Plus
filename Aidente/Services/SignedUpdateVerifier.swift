import Foundation
import Security

enum SignedUpdateVerifier {
    static func verify(candidate:URL,installed:URL) throws {
        var current:SecStaticCode?
        guard SecStaticCodeCreateWithPath(installed as CFURL,[],&current) == errSecSuccess,let current,
              SecStaticCodeCheckValidity(current,[],nil) == errSecSuccess else { throw failure() }
        var info:CFDictionary?
        guard SecCodeCopySigningInformation(current,SecCSFlags(rawValue:kSecCSSigningInformation),&info) == errSecSuccess,
              let fields=info as? [String:Any],let team=fields[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty,team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw failure() }
        let rule="anchor apple generic and identifier \"com.aidente.app\" and certificate leaf[subject.OU] = \"\(team)\""
        var requirement:SecRequirement?,code:SecStaticCode?
        guard SecRequirementCreateWithString(rule as CFString,[],&requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(candidate as CFURL,[],&code) == errSecSuccess,let code,let requirement,
              SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSCheckAllArchitectures | kSecCSCheckNestedCode),requirement) == errSecSuccess else { throw failure() }
    }
    private static func failure()->NSError {
        NSError(domain:"Aidente.UpdateSignature",code:1,userInfo:[NSLocalizedDescriptionKey:"更新包必须由与当前 Aidente 相同的 Apple 开发者身份签名；无法验证时请使用发行页安装包。"])
    }
}
