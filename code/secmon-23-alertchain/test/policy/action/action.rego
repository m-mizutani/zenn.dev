package action

github_args := {
    "app_id": 134650,
    "install_id": 19102538,
    "owner": "m-mizutani",
    "repo": "security-alert",
    "secret_private_key": input.env.GITHUB_PRIVATE_KEY,
}

issue_num := input.alert.attrs[x].value if {
    input.alert.attrs[x].key == "github_issue_number"
}

# (1) GitHub issue number が存在しなければIssueを作成
run contains {
    "id": "github-issue",
    "uses": "github.create_issue",
    "args": github_args,
    "commit": [
        {
            "key": "github_issue_number",
            "persist": true,
            "path": "number",
        },
    ],
} if {
    input.seq == 0
    not issue_num
}

# (2) GitHub issue number が存在するなら、それをもとにコメントを作成
run contains {
    "id": "github-comment",
    "uses": "github.create_comment",
    "args": object.union(github_args, {
        "body": "dup!",
        "issue_number": issue_num,
    }),
} if {
    input.seq == 0
    issue_num > 0
}
