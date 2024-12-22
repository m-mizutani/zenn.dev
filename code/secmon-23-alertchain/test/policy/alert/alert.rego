package alert.aws_guardduty

alert contains {
	"title": f.Type,
	"source": "aws",
	"attrs": [{
		"key": "instance ID",
		"value": f.Resource.InstanceDetails.InstanceId,
	}],
    "namespace": sprintf("aws_guardduty_trojan_alert/instance/%s", [f.Resource.InstanceDetails.InstanceId]),
} if {
	f := input.Findings[_]
	startswith(f.Type, "Trojan:")
	f.Severity > 7
}
