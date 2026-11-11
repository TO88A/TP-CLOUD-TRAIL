# RÈGLE 2 — Refuser toute ressource étiquetable sans étiquette "owner".
#
# Une ressource est étiquetable si son schéma possède l'attribut "tags" : la
# clé est alors présente dans change.after, même à null. Les ressources sans
# étiquettes possibles (aws_iam_group, aws_s3_bucket_versioning...) sont ignorées.
#
# Valeur inconnue : si "tags" est inconnu au plan, on REFUSE (fail-closed).
# On lit "tags" (déclaré dans le code) et non "tags_all", qui est
# "known after apply" quand aucune étiquette n'est déclarée.
package main

import data.lib.tfplan

required_tags := {"owner"}

taggable(rc) if "tags" in object.keys(rc.change.after)

# Un attribut inconnu est ABSENT de "after" et présent dans "after_unknown"
# (défaut trouvé par le test test_tags_unknown_denied_fail_closed).
taggable(rc) if tfplan.is_unknown(rc, "tags")

tag_value(rc, key) := v if {
	tags := rc.change.after.tags
	is_object(tags)
	v := tags[key]
	is_string(v)
	trim_space(v) != ""
}

deny contains msg if {
	some rc in tfplan.resources
	taggable(rc)
	not tfplan.is_unknown(rc, "tags")
	some key in required_tags
	not tag_value(rc, key)
	msg := sprintf("[TAG-001] %s (%s) : étiquette obligatoire \"%s\" absente ou vide.", [rc.address, rc.type, key])
}

deny contains msg if {
	some rc in tfplan.resources
	taggable(rc)
	tfplan.is_unknown(rc, "tags")
	msg := sprintf("[TAG-001] %s : étiquettes inconnues avant apply, impossible de vérifier \"owner\" (fail-closed).", [rc.address])
}

# Avertissement (non bloquant) : "env" est aussi exigée par l'énoncé (Partie 3).
warn contains msg if {
	some rc in tfplan.resources
	taggable(rc)
	not tfplan.is_unknown(rc, "tags")
	not tag_value(rc, "env")
	msg := sprintf("[TAG-002] %s : étiquette \"env\" absente.", [rc.address])
}
