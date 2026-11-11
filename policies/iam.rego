# RÈGLE 1 — Refuser toute politique IAM qui autorise Action "*".
#
# Couvre les politiques d'identité (utilisateur, groupe, rôle, gérées) ET les
# politiques de ressource S3, qui utilisent le même langage.
# Une déclaration Deny avec "*" est restrictive : elle est donc tolérée.
#
# Valeur inconnue : si le document n'est pas calculable au plan (il dépend
# d'un attribut "known after apply"), on REFUSE (fail-closed). Une politique
# qu'on ne peut pas vérifier n'est pas acceptée. Le code construit donc ses
# ARN à partir d'attributs connus au plan (voir SYNTHESE.md).
package main

import data.lib.tfplan

policy_types := {
	"aws_iam_policy",
	"aws_iam_user_policy",
	"aws_iam_group_policy",
	"aws_iam_role_policy",
	"aws_s3_bucket_policy",
}

wildcard_actions := {"*", "*:*"}

# Documents de politique connus au plan
policy_doc(rc) := json.unmarshal(rc.change.after.policy) if {
	is_string(rc.change.after.policy)
	rc.change.after.policy != ""
}

deny contains msg if {
	some rc in tfplan.resources
	rc.type in policy_types
	doc := policy_doc(rc)
	some st in tfplan.statements(doc)
	st.Effect == "Allow"
	some action in tfplan.as_array(st.Action)
	action in wildcard_actions
	msg := sprintf("[IAM-001] %s : la politique autorise Action \"%s\" (Sid=%v). Listez les actions précises (moindre privilège).", [rc.address, action, object.get(st, "Sid", "-")])
}

# NotAction dans un Allow autorise tout SAUF la liste : c'est aussi large que "*".
deny contains msg if {
	some rc in tfplan.resources
	rc.type in policy_types
	doc := policy_doc(rc)
	some st in tfplan.statements(doc)
	st.Effect == "Allow"
	st.NotAction
	msg := sprintf("[IAM-001] %s : \"NotAction\" dans une déclaration Allow équivaut à un joker. Utilisez Action avec une liste explicite.", [rc.address])
}

deny contains msg if {
	some rc in tfplan.resources
	rc.type in policy_types
	tfplan.is_unknown(rc, "policy")
	msg := sprintf("[IAM-001] %s : document de politique inconnu avant apply, impossible à vérifier (fail-closed). Construisez les ARN à partir d'attributs connus au plan.", [rc.address])
}

# Avertissement (non bloquant) : joker sur tout un service, ex. "s3:*".
warn contains msg if {
	some rc in tfplan.resources
	rc.type in policy_types
	doc := policy_doc(rc)
	some st in tfplan.statements(doc)
	st.Effect == "Allow"
	some action in tfplan.as_array(st.Action)
	endswith(action, ":*")
	msg := sprintf("[IAM-002] %s : action \"%s\" couvre tout un service ; préférez des actions précises.", [rc.address, action])
}
