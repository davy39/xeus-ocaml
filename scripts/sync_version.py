import re
import sys
import hashlib
from pathlib import Path
from ruamel.yaml import YAML
import urllib.request
from urllib.error import HTTPError

SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
HEADER_PATH = PROJECT_ROOT / "include" / "xeus_ocaml_config.hpp"
RECIPE_PATH = PROJECT_ROOT / "recipe" / "recipe-prod.yaml"
GITHUB_OWNER = "davy39" 
GITHUB_REPO = "xeus-ocaml" 
# ---

def get_version_from_header():
    """Parses the C++ header to extract the version components."""
    try:
        header_content = HEADER_PATH.read_text()
    except FileNotFoundError:
        raise RuntimeError(f"Header file not found at: {HEADER_PATH}")
    
    major_match = re.search(r"#define XEUS_OCAML_VERSION_MAJOR\s+(\d+)", header_content)
    minor_match = re.search(r"#define XEUS_OCAML_VERSION_MINOR\s+(\d+)", header_content)
    patch_match = re.search(r"#define XEUS_OCAML_VERSION_PATCH\s+(\d+)", header_content)
    
    if not (major_match and minor_match and patch_match):
        raise RuntimeError(f"Could not parse version from {HEADER_PATH}")
    
    major = major_match.group(1)
    minor = minor_match.group(1)
    patch = patch_match.group(1)
    
    return f"{major}.{minor}.{patch}"

def get_github_tarball_sha256(version):
    """
    Downloads the source tarball from GitHub and computes its SHA256.
    
    Args:
        version: Version tag (e.g., "1.2.3" for tag "v1.2.3")
    
    Returns:
        SHA256 hash as a hexadecimal string
    """
    tag = f"v{version}"
    url = f"https://github.com/{GITHUB_OWNER}/{GITHUB_REPO}/archive/refs/tags/{tag}.tar.gz"
    
    print(f"Downloading tarball from {url}...", file=sys.stderr)
    
    try:
        with urllib.request.urlopen(url) as response:
            sha256_hash = hashlib.sha256()
            # Read in chunks to avoid loading the entire file into memory
            while chunk := response.read(8192):
                sha256_hash.update(chunk)
        
        return sha256_hash.hexdigest()
    except HTTPError as e:
        if e.code == 404:
            raise RuntimeError(f"Tag {tag} not found on GitHub. Make sure the release exists.")
        raise RuntimeError(f"HTTP Error {e.code} while downloading the tarball")
    except Exception as e:
        raise RuntimeError(f"Error while downloading the tarball: {e}")

def main(check_only=False, show_sha=False):
    """Main function to synchronize or check the version."""
    try:
        header_version = get_version_from_header()
    except (RuntimeError, FileNotFoundError) as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    
    # If we just want the SHA256
    if show_sha:
        try:
            sha256 = get_github_tarball_sha256(header_version)
            print(sha256)  # Clean output for use in scripts
            sys.exit(0)
        except RuntimeError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
    
    yaml = YAML()
    # The default 'rt' (round-trip) mode preserves comments and formatting.
    
    try:
        recipe_data = yaml.load(RECIPE_PATH)
    except FileNotFoundError:
        print(f"Error: Recipe file not found at: {RECIPE_PATH}", file=sys.stderr)
        sys.exit(1)
    
    recipe_version = str(recipe_data['context']['version'])
    
    if header_version == recipe_version:
        print(f"Versions are in sync: {header_version}")
        sys.exit(0)
    
    if check_only:
        print(
            f"Error: Versions do not match!\n"
            f"  Header ({HEADER_PATH}): {header_version}\n"
            f"  Recipe ({RECIPE_PATH}): {recipe_version}\n"
            f"Please run 'pixi run sync-version' and commit the changes.",
            file=sys.stderr,
        )
        sys.exit(1)
    else:
        print(f"Updating recipe version from {recipe_version} to {header_version}...")
        recipe_data['context']['version'] = header_version
        yaml.dump(recipe_data, RECIPE_PATH)
        print("Done.")

if __name__ == "__main__":
    is_check = "--check" in sys.argv
    is_sha = "--sha" in sys.argv or "--sha256" in sys.argv
    main(check_only=is_check, show_sha=is_sha)