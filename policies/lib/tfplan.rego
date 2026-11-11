# Fonctions communes pour lire un plan Terraform JSON (terraform show -json).
# Syntaxe Rego v1 (OPA >= 1.0, Conftest >= 0.56).
package lib.tfplan

# Ressources qui EXISTERONT après apply : on écarte les suppressions pures.
# Les "no-op" sont gardées : elles décrivent l'état final de la ressource.
resources contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	not is_pure_delete(rc)
	rc.change.after != null
}

is_pure_delete(rc) if rc.change.actions == ["delete"]

# Valeur inconnue avant apply (after_unknown[attr] == true)
is_unknown(rc, attr) if rc.change.after_unknown[attr] == true

# Normalise un champ IAM qui peut être une chaîne OU une liste
as_array(x) := x if is_array(x)

as_array(x) := [x] if is_string(x)

# Liste des déclarations d'un document de politique (objet ou liste)
statements(doc) := as_array_obj(doc.Statement)

as_array_obj(x) := x if is_array(x)

as_array_obj(x) := [x] if is_object(x)
