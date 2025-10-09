import re
import sys
from pathlib import Path
from ruamel.yaml import YAML

# --- Configuration ---
# Obtient les chemins relatifs à l'emplacement du script
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
HEADER_PATH = PROJECT_ROOT / "include" / "xeus_ocaml_config.hpp"
RECIPE_PATH = PROJECT_ROOT / "recipe" / "recipe.yaml"
# ---

def get_version_from_header():
    """Analyse l'en-tête C++ pour en extraire les composants de la version."""
    try:
        header_content = HEADER_PATH.read_text()
    except FileNotFoundError:
        raise RuntimeError(f"Fichier d'en-tête introuvable à : {HEADER_PATH}")
    
    major_match = re.search(r"#define XEUS_OCAML_VERSION_MAJOR\s+(\d+)", header_content)
    minor_match = re.search(r"#define XEUS_OCAML_VERSION_MINOR\s+(\d+)", header_content)
    patch_match = re.search(r"#define XEUS_OCAML_VERSION_PATCH\s+(\d+)", header_content)
    
    if not (major_match and minor_match and patch_match):
        raise RuntimeError(f"Impossible d'analyser la version depuis {HEADER_PATH}")
        
    major = major_match.group(1)
    minor = minor_match.group(1)
    patch = patch_match.group(1)
        
    return f"{major}.{minor}.{patch}"

def main(check_only=False):
    """Fonction principale pour synchroniser ou vérifier la version."""
    try:
        header_version = get_version_from_header()
    except (RuntimeError, FileNotFoundError) as e:
        print(f"Erreur : {e}", file=sys.stderr)
        sys.exit(1)

    yaml = YAML()
    # Le mode par défaut 'rt' (round-trip) préserve les commentaires et la mise en forme.
    # La ligne yaml.preserve_quotes = True a été supprimée car elle est inutile ici et causait l'erreur.
    
    try:
        recipe_data = yaml.load(RECIPE_PATH)
    except FileNotFoundError:
        print(f"Erreur : Fichier recette introuvable à : {RECIPE_PATH}", file=sys.stderr)
        sys.exit(1)
    
    recipe_version = str(recipe_data['context']['version'])

    if header_version == recipe_version:
        print(f"Les versions sont synchronisées : {header_version}")
        sys.exit(0)

    if check_only:
        print(
            f"Erreur : Les versions ne correspondent pas !\n"
            f"  En-tête ({HEADER_PATH}):    {header_version}\n"
            f"  Recette ({RECIPE_PATH}): {recipe_version}\n"
            f"Veuillez lancer 'pixi run sync-version' et committer les changements.",
            file=sys.stderr,
        )
        sys.exit(1)
    else:
        print(f"Mise à jour de la version de la recette de {recipe_version} à {header_version}...")
        recipe_data['context']['version'] = header_version
        yaml.dump(recipe_data, RECIPE_PATH)
        print("Terminé.")

if __name__ == "__main__":
    is_check = "--check" in sys.argv
    main(check_only=is_check)