# RÈGLE 3 (notre choix) — Chaque bucket S3 doit avoir un Public Access Block
# COMPLET : les 4 verrous à true.
#
# Pourquoi cette règle :
#  - Le risque n° 1 de NovaCorp est l'exposition publique des données clients
#    (novacorp-customer-data) : une fuite S3 publique est l'incident cloud le
#    plus fréquent.
#  - Checkov et Trivy vérifient le CODE. Un développeur peut les contourner avec
#    un simple commentaire #checkov:skip, et les valeurs qui viennent de
#    variables ou de modules leur échappent en partie. Cette règle vérifie le
#    PLAN, c'est-à-dire les valeurs réellement envoyées à AWS, une fois
#    variables et modules résolus.
#  - Elle couvre les deux cas : verrou absent, ou verrou présent mais
#    désactivé (par exemple block_public_policy = var.allow_public).
#
# Relier un PAB à son bucket : on compare after.bucket (nom du bucket). Le code
# référence aws_s3_bucket.x.bucket, connu au plan. Si le nom n'est pas connu,
# on refuse (fail-closed).
package main

import data.lib.tfplan

pab_flags := {"block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"}

buckets contains rc if {
	some rc in tfplan.resources
	rc.type == "aws_s3_bucket"
}

pabs contains rc if {
	some rc in tfplan.resources
	rc.type == "aws_s3_bucket_public_access_block"
}

pab_for(bucket_name) := pab if {
	some pab in pabs
	pab.change.after.bucket == bucket_name
}

# 1. Bucket sans aucun Public Access Block
deny contains msg if {
	some b in buckets
	name := b.change.after.bucket
	is_string(name)
	not pab_for(name)
	msg := sprintf("[S3-001] %s : le bucket \"%s\" n'a pas de aws_s3_bucket_public_access_block (risque d'exposition publique).", [b.address, name])
}

# 2. Public Access Block présent mais incomplet
deny contains msg if {
	some pab in pabs
	some flag in pab_flags
	pab.change.after[flag] != true
	msg := sprintf("[S3-001] %s : \"%s\" doit valoir true (bucket \"%v\").", [pab.address, flag, object.get(pab.change.after, "bucket", "?")])
}

# 3. Liens impossibles à vérifier au plan (fail-closed)
deny contains msg if {
	some b in buckets
	tfplan.is_unknown(b, "bucket")
	msg := sprintf("[S3-001] %s : nom de bucket inconnu avant apply, impossible de vérifier le blocage d'accès public (fail-closed).", [b.address])
}

deny contains msg if {
	some pab in pabs
	tfplan.is_unknown(pab, "bucket")
	msg := sprintf("[S3-001] %s : bucket cible inconnu avant apply ; référencez aws_s3_bucket.<nom>.bucket plutôt que .id (fail-closed).", [pab.address])
}
