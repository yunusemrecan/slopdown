// SPDX-License-Identifier: GPL-3.0-or-later
//
// The "vibe-coded" notice, shown in the About window in the user's language.
// Keep in sync with the table at the top of README.md.

import Foundation

public enum Disclaimer {
    public static let title = "Vibe-coded"

    /// Language code → notice. English is the fallback.
    public static let notices: [(code: String, name: String, text: String)] = [
        ("en", "English", "This app is vibe-coded: it was written by an AI (Claude), not by a human programmer. Its owner directs and reviews it but did not write the code. Use it at your own risk and keep backups of your notes."),
        ("tr", "Türkçe", "Bu uygulama vibe-coded'dur: kodunu bir insan programcı değil, bir yapay zekâ (Claude) yazdı. Sahibi yönlendiriyor ve gözden geçiriyor ama kodu kendisi yazmadı. Kullanım sorumluluğu size aittir; notlarınızın yedeğini alın."),
        ("de", "Deutsch", "Diese App ist „vibe-coded“: Sie wurde von einer KI (Claude) geschrieben, nicht von einem menschlichen Programmierer. Der Inhaber steuert und prüft sie, hat den Code aber nicht selbst geschrieben. Nutzung auf eigene Gefahr – sichern Sie Ihre Notizen."),
        ("fr", "Français", "Cette application est « vibe-codée » : elle a été écrite par une IA (Claude), et non par un programmeur humain. Son propriétaire la dirige et la relit, mais n’a pas écrit le code. Utilisation à vos risques ; sauvegardez vos notes."),
        ("es", "Español", "Esta aplicación está hecha con «vibe coding»: la escribió una IA (Claude), no un programador humano. Su propietario la dirige y la revisa, pero no escribió el código. Úsala bajo tu propia responsabilidad y haz copias de seguridad de tus notas."),
        ("it", "Italiano", "Questa app è «vibe-coded»: è stata scritta da un’IA (Claude), non da un programmatore umano. Il proprietario la dirige e la revisiona, ma non ha scritto il codice. Usala a tuo rischio e fai un backup delle tue note."),
        ("pt", "Português", "Este app foi feito com “vibe coding”: foi escrito por uma IA (Claude), não por um programador humano. O dono o orienta e revisa, mas não escreveu o código. Use por sua conta e risco e faça backup das suas notas."),
        ("ru", "Русский", "Это приложение создано в стиле «вайб-кодинга»: код написал ИИ (Claude), а не программист-человек. Владелец направляет и проверяет работу, но сам код не писал. Используйте на свой риск и делайте резервные копии заметок."),
        ("ar", "العربية", "هذا التطبيق مبرمج بأسلوب «البرمجة بالإحساس» (vibe coding): كتبه ذكاء اصطناعي (Claude) وليس مبرمجًا بشريًا. يوجّهه مالكه ويراجعه، لكنه لم يكتب الشيفرة بنفسه. استخدمه على مسؤوليتك واحتفظ بنسخ احتياطية من ملاحظاتك."),
        ("ja", "日本語", "このアプリは「バイブコーディング」で作られています。コードを書いたのは人間のプログラマーではなく AI（Claude）です。所有者は方向性を決めてレビューしていますが、コード自体は書いていません。自己責任でご使用のうえ、ノートのバックアップを取ってください。"),
        ("zh", "中文", "本应用是“氛围编程”（vibe coding）的产物：代码由 AI（Claude）编写，而非人类程序员。所有者负责指导和审阅，但没有亲自编写代码。使用风险自负，请备份你的笔记。"),
        ("ko", "한국어", "이 앱은 '바이브 코딩'으로 만들어졌습니다. 코드는 사람 프로그래머가 아니라 AI(Claude)가 작성했습니다. 소유자가 방향을 정하고 검토하지만 코드를 직접 작성하지는 않았습니다. 사용에 따른 책임은 본인에게 있으며, 노트는 꼭 백업하세요."),
    ]

    /// Notice in the first of the preferred languages we have, else English.
    public static func text(for preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        for lang in preferredLanguages {
            let code = String(lang.lowercased().prefix(while: { $0 != "-" && $0 != "_" }))
            if let n = notices.first(where: { $0.code == code }) { return n.text }
        }
        return notices[0].text
    }
}
