local event = import "../../policy/alert/testdata/guardduty/data.json";

{
  id: 'scenario1',
  title: 'AWS GuardDuty Trojan alert',
  events: [
    {
      input: event,
      schema: 'aws_guardduty',
      actions: {
        'github.create_issue': [{
          number: 999,
        }],
      },
    },
    {
      input: event,
      schema: 'aws_guardduty',
    },
  ],
  env: {
    GITHUB_PRIVATE_KEY: 'test_private_key_xxxxxxxxxx',
  },
}
