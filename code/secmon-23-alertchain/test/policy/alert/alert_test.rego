package alert.aws_guardduty

test_alert if {
	resp := alert with input as data.testdata.guardduty
	count(resp) == 1
	a := resp[_]
	a.title == "Trojan:EC2/DropPoint!DNS"
	count(a.attrs) == 1
	a.attrs[x].key == "instance ID"
	a.attrs[x].value == "i-99999999"
}

test_not_enough_severity if {
	resp := alert with input as json.patch(data.testdata.guardduty, [
        {
            "op": "replace",
            "path": "/Findings/0/Severity",
            "value": 7
        }
    ])

	count(resp) == 0
}

test_not_trojan if {
    resp := alert with input as json.patch(data.testdata.guardduty, [
        {
            "op": "replace",
            "path": "/Findings/0/Type",
            "value": "Not a Trojan"
        }
    ])

    count(resp) == 0
}