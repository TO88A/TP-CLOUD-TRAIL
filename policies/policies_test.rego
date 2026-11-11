# Tests unitaires des règles : conftest verify -p policies
package main

import rego.v1

# --- Fabriques d'entrées minimales -------------------------------------------
rc(addr, type, after) := {
	"address": addr, "mode": "managed", "type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}

rc_unknown(addr, type, after, unknown) := {
	"address": addr, "mode": "managed", "type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": unknown},
}

pol(stmts) := json.marshal({"Version": "2012-10-17", "Statement": stmts})

good_tags := {"owner": "team-platform", "env": "dev"}

full_pab(b) := {
	"bucket": b, "block_public_acls": true, "block_public_policy": true,
	"ignore_public_acls": true, "restrict_public_buckets": true,
}

# --- Règle 1 : IAM Action "*" -------------------------------------------------
test_iam_star_string_denied if {
	inp := {"resource_changes": [rc("p", "aws_iam_user_policy", {"policy": pol([{"Effect": "Allow", "Action": "*", "Resource": "*"}])})]}
	count(deny) == 1 with input as inp
}

test_iam_star_in_list_denied if {
	inp := {"resource_changes": [rc("p", "aws_iam_group_policy", {"policy": pol([{"Effect": "Allow", "Action": ["s3:GetObject", "*"], "Resource": "arn:aws:s3:::b/*"}])})]}
	count(deny) == 1 with input as inp
}

test_iam_single_statement_object_denied if {
	doc := json.marshal({"Version": "2012-10-17", "Statement": {"Effect": "Allow", "Action": "*:*", "Resource": "*"}})
	inp := {"resource_changes": [rc("p", "aws_iam_policy", {"policy": doc, "tags": good_tags})]}
	count(deny) == 1 with input as inp
}

test_iam_notaction_denied if {
	inp := {"resource_changes": [rc("p", "aws_iam_role_policy", {"policy": pol([{"Effect": "Allow", "NotAction": "iam:*", "Resource": "*"}])})]}
	count(deny) == 1 with input as inp
}

test_iam_deny_star_allowed if {
	inp := {"resource_changes": [rc("p", "aws_iam_group_policy", {"policy": pol([{"Effect": "Deny", "Action": "*", "Resource": "*"}])})]}
	count(deny) == 0 with input as inp
}

test_iam_least_privilege_allowed if {
	inp := {"resource_changes": [rc("p", "aws_iam_group_policy", {"policy": pol([{"Effect": "Allow", "Action": ["s3:PutObject"], "Resource": "arn:aws:s3:::novacorp-logs/app/*"}])})]}
	count(deny) == 0 with input as inp
}

test_iam_unknown_policy_denied_fail_closed if {
	inp := {"resource_changes": [rc_unknown("p", "aws_iam_group_policy", {}, {"policy": true})]}
	count(deny) == 1 with input as inp
}

test_iam_service_wildcard_warns_only if {
	inp := {"resource_changes": [rc("p", "aws_iam_group_policy", {"policy": pol([{"Effect": "Allow", "Action": "s3:*", "Resource": "arn:aws:s3:::b/*"}])})]}
	count(deny) == 0 with input as inp
	count(warn) == 1 with input as inp
}

test_iam_deleted_resource_ignored if {
	r := {"address": "p", "mode": "managed", "type": "aws_iam_user_policy", "change": {"actions": ["delete"], "after": null, "after_unknown": {}}}
	count(deny) == 0 with input as {"resource_changes": [r]}
}

# --- Règle 2 : étiquette owner ------------------------------------------------
test_tags_missing_owner_denied if {
	inp := {"resource_changes": [rc("u", "aws_iam_user", {"name": "u", "tags": {"env": "dev"}})]}
	count(deny) == 1 with input as inp
}

test_tags_null_denied if {
	inp := {"resource_changes": [rc("u", "aws_iam_user", {"name": "u", "tags": null})]}
	count(deny) == 1 with input as inp
}

test_tags_empty_owner_denied if {
	inp := {"resource_changes": [rc("u", "aws_iam_user", {"name": "u", "tags": {"owner": "  ", "env": "dev"}})]}
	count(deny) == 1 with input as inp
}

test_tags_ok if {
	inp := {"resource_changes": [rc("u", "aws_iam_user", {"name": "u", "tags": good_tags})]}
	count(deny) == 0 with input as inp
}

test_tags_non_taggable_ignored if {
	inp := {"resource_changes": [rc("g", "aws_iam_group", {"name": "g"})]}
	count(deny) == 0 with input as inp
}

test_tags_unknown_denied_fail_closed if {
	inp := {"resource_changes": [rc_unknown("u", "aws_iam_user", {"name": "u"}, {"tags": true})]}
	count(deny) == 1 with input as inp
}

# --- Règle 3 : Public Access Block complet ------------------------------------
test_s3_without_pab_denied if {
	inp := {"resource_changes": [rc("b", "aws_s3_bucket", {"bucket": "x", "tags": good_tags})]}
	count(deny) == 1 with input as inp
}

test_s3_pab_partial_denied if {
	pab := object.union(full_pab("x"), {"restrict_public_buckets": false})
	inp := {"resource_changes": [
		rc("b", "aws_s3_bucket", {"bucket": "x", "tags": good_tags}),
		rc("p", "aws_s3_bucket_public_access_block", pab),
	]}
	count(deny) == 1 with input as inp
}

test_s3_pab_on_other_bucket_denied if {
	inp := {"resource_changes": [
		rc("b", "aws_s3_bucket", {"bucket": "x", "tags": good_tags}),
		rc("p", "aws_s3_bucket_public_access_block", full_pab("y")),
	]}
	count(deny) == 1 with input as inp
}

test_s3_pab_complete_ok if {
	inp := {"resource_changes": [
		rc("b", "aws_s3_bucket", {"bucket": "x", "tags": good_tags}),
		rc("p", "aws_s3_bucket_public_access_block", full_pab("x")),
	]}
	count(deny) == 0 with input as inp
}

test_s3_pab_unknown_bucket_denied_fail_closed if {
	inp := {"resource_changes": [
		rc("b", "aws_s3_bucket", {"bucket": "x", "tags": good_tags}),
		rc_unknown("p", "aws_s3_bucket_public_access_block", object.remove(full_pab("x"), ["bucket"]), {"bucket": true}),
	]}
	# 2 refus : PAB non relié (inconnu) + bucket x sans PAB vérifiable
	count(deny) == 2 with input as inp
}
