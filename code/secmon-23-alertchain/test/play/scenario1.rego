package play

test_scenario1 if {
    s := data.output.scenario1

    # シナリオIDがあっているかチェック
    s.id == "scenario1"
    # Alertが2回受入られている
    count(s.results) == 2

    # === 1回目の受入 ===
    # ✅️ アラートについてのチェック
    s.results[0].alert.title == "Trojan:EC2/DropPoint!DNS"
    # ✅️ 1つ目のアクションはGitHub Issueの作成
    s.results[0].actions[0].uses == "github.create_issue"
    # ✅️ GitHub Issueの作成時に指定された引数のチェック
    s.results[0].actions[0].args["app_id"] == 134650
    # ✅️ Issue作成時の返り値のチェック
    s.results[0].actions[0].commit[x].key == "github_issue_number"
    s.results[0].actions[0].commit[x].value == 999

    # === 2回目の受入 ===
    # ✅️ アラートについてのチェック
    s.results[1].alert.title == "Trojan:EC2/DropPoint!DNS"
    # ✅️ 2つ目のアクションはGitHub Issueのコメント作成
    s.results[1].actions[0].uses == "github.create_comment"
    # ✅️ GitHub Issueのコメント作成時に指定された引数のチェック
    s.results[1].actions[0].args["issue_number"] == 999
}
