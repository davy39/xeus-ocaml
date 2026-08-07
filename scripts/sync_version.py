import re
import sys
import hashlib
import tomllib
from pathlib import Path
from ruamel.yaml import YAML
import urllib.request
from urllib.error import HTTPError

SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
PIXI_TOML_PATH = PROJECT_ROOT / "pixi.toml"
HEADER_PATH = PROJECT_ROOT / "include" / "xeus_ocaml_config.hpp"
RECIPE_PROD_PATH = PROJECT_ROOT / "recipe" / "recipe-prod.yaml"
RECIPE_DEV_PATH = PROJECT_ROOT / "recipe" / "recipe-dev.yaml"
DUNE_PROJECT_PATH = PROJECT_ROOT / "ocaml" / "dune-project"
GITHUB_OWNER = "davy39"
GITHUB_REPO = "xeus-ocaml"


def get_versions_from_pixi_toml():
    """Parses pixi.toml to extract the single source of truth versions.

    Returns:
        tuple (project_version, ocaml_version), e.g. ("0.2.8", "5.5.0").
    """
    try:
        data = tomllib.loads(PIXI_TOML_PATH.read_text())
    except FileNotFoundError:
        raise RuntimeError(f"pixi.toml not found at: {PIXI_TOML_PATH}")
    except tomllib.TOMLDecodeError as e:
        raise RuntimeError(f"Could not parse {PIXI_TOML_PATH}: {e}")

    project_version = data.get("workspace", {}).get("version")
    ocaml_version = data.get("activation", {}).get("env", {}).get("XEUS_OCAML_OCAML_VERSION")

    if not project_version:
        raise RuntimeError(
            "Missing [workspace].version in pixi.toml (single source of truth for the project version)."
        )
    if not ocaml_version:
        raise RuntimeError(
            "Missing [activation.env].XEUS_OCAML_OCAML_VERSION in pixi.toml "
            "(single source of truth for the OCaml compiler version)."
        )
    return str(project_version), str(ocaml_version)


def read_header_version():
    """Reads the version currently defined in the C++ header."""
    header_content = HEADER_PATH.read_text()
    major = re.search(r"#define XEUS_OCAML_VERSION_MAJOR\s+(\d+)", header_content)
    minor = re.search(r"#define XEUS_OCAML_VERSION_MINOR\s+(\d+)", header_content)
    patch = re.search(r"#define XEUS_OCAML_VERSION_PATCH\s+(\d+)", header_content)
    if not (major and minor and patch):
        raise RuntimeError(f"Could not parse version from {HEADER_PATH}")
    return f"{major.group(1)}.{minor.group(1)}.{patch.group(1)}"


def update_header(project_version):
    """Rewrites the MAJOR/MINOR/PATCH defines in the C++ header."""
    major, minor, patch = project_version.split(".")
    header_content = HEADER_PATH.read_text()

    def replace(name, value):
        pattern = re.compile(r"(#define " + name + r")\s+\d+")
        return pattern.sub(r"\g<1> " + value, header_content)

    updated = header_content
    updated = replace("XEUS_OCAML_VERSION_MAJOR", major)
    updated = replace("XEUS_OCAML_VERSION_MINOR", minor)
    updated = replace("XEUS_OCAML_VERSION_PATCH", patch)

    if updated != header_content:
        HEADER_PATH.write_text(updated)
        print(f"Updated {HEADER_PATH.relative_to(PROJECT_ROOT)} to {project_version}")
    return updated


def update_recipe(path, project_version, ocaml_version):
    """Updates context.version and context.ocaml_version in a recipe file."""
    yaml = YAML()
    recipe_data = yaml.load(path)
    recipe_data["context"]["version"] = project_version
    recipe_data["context"]["ocaml_version"] = ocaml_version
    yaml.dump(recipe_data, path)
    print(f"Updated {path.relative_to(PROJECT_ROOT)} to {project_version} (ocaml {ocaml_version})")


def read_recipe_versions(path):
    """Reads context.version and context.ocaml_version from a recipe file."""
    yaml = YAML()
    recipe_data = yaml.load(path)
    context = recipe_data.get("context", {})
    return str(context.get("version", "")), str(context.get("ocaml_version", ""))


def update_dune_project(project_version):
    """Rewrites the (version ...) field in ocaml/dune-project."""
    content = DUNE_PROJECT_PATH.read_text()
    updated, count = re.subn(r"\(version\s+[\d.]+\)", f"(version {project_version})", content)
    if count == 0:
        raise RuntimeError(f"Could not find (version ...) in {DUNE_PROJECT_PATH}")
    if updated != content:
        DUNE_PROJECT_PATH.write_text(updated)
        print(f"Updated {DUNE_PROJECT_PATH.relative_to(PROJECT_ROOT)} to {project_version}")


def read_dune_project_version():
    """Reads the version from ocaml/dune-project."""
    content = DUNE_PROJECT_PATH.read_text()
    match = re.search(r"\(version\s+([\d.]+)\)", content)
    if not match:
        raise RuntimeError(f"Could not find (version ...) in {DUNE_PROJECT_PATH}")
    return match.group(1)


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


def collect_versions():
    """Returns a dict of every version location and its current value."""
    project_version, ocaml_version = get_versions_from_pixi_toml()
    header_version = read_header_version()
    prod_version, prod_ocaml = read_recipe_versions(RECIPE_PROD_PATH)
    dev_version, dev_ocaml = read_recipe_versions(RECIPE_DEV_PATH)
    dune_version = read_dune_project_version()

    return {
        "pixi.toml [workspace].version": ("project", project_version),
        "include/xeus_ocaml_config.hpp": ("project", header_version),
        "recipe/recipe-prod.yaml (context.version)": ("project", prod_version),
        "recipe/recipe-dev.yaml (context.version)": ("project", dev_version),
        "ocaml/dune-project (version)": ("project", dune_version),
        "recipe/recipe-prod.yaml (context.ocaml_version)": ("ocaml", prod_ocaml),
        "recipe/recipe-dev.yaml (context.ocaml_version)": ("ocaml", dev_ocaml),
    }


def check_sync():
    """Verifies every version location matches the pixi.toml source of truth."""
    project_version, ocaml_version = get_versions_from_pixi_toml()
    locations = collect_versions()

    mismatches = []
    for label, (kind, value) in locations.items():
        expected = project_version if kind == "project" else ocaml_version
        if value != expected:
            mismatches.append(f"  {label}: {value} (expected {expected})")

    if mismatches:
        print("Error: Versions do not match!\n" + "\n".join(mismatches), file=sys.stderr)
        print("Please run 'pixi run sync-version' and commit the changes.", file=sys.stderr)
        sys.exit(1)

    print(f"Versions are in sync: project {project_version}, ocaml {ocaml_version}")


def main(check_only=False, show_sha=False):
    """Main function to synchronize or check the versions."""
    project_version, ocaml_version = get_versions_from_pixi_toml()

    # If we just want the SHA256 of the current version's tarball
    if show_sha:
        try:
            sha256 = get_github_tarball_sha256(project_version)
            print(sha256)  # Clean output for use in scripts
            sys.exit(0)
        except RuntimeError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)

    if check_only:
        check_sync()
        sys.exit(0)

    print(f"Syncing from pixi.toml: project {project_version}, ocaml {ocaml_version}")
    update_header(project_version)
    update_recipe(RECIPE_PROD_PATH, project_version, ocaml_version)
    update_recipe(RECIPE_DEV_PATH, project_version, ocaml_version)
    update_dune_project(project_version)
    print("Done. All versions are now in sync with pixi.toml.")


if __name__ == "__main__":
    is_check = "--check" in sys.argv
    is_sha = "--sha" in sys.argv or "--sha256" in sys.argv
    main(check_only=is_check, show_sha=is_sha)
