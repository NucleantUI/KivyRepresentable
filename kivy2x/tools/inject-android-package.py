"""
Inject the `android` package from a pre-built android wheel into every Kivy
wheel in dest_dir that matches the same ABI.

Usage:
    python inject-android-package.py <dest_dir> <android_wheels_dir>
"""
import argparse
import os
import zipfile


def get_abi_tag(wheel_name):
    """Return normalised ABI tag from a wheel filename platform tag."""
    if "arm64_v8a" in wheel_name or "aarch64" in wheel_name:
        return "arm64_v8a"
    elif "x86_64" in wheel_name:
        return "x86_64"
    return None


def find_android_wheel(android_wheels_dir, abi_tag):
    for name in os.listdir(android_wheels_dir):
        if name.endswith(".whl") and get_abi_tag(name) == abi_tag:
            return os.path.join(android_wheels_dir, name)
    return None


def inject_android_package(dest_dir, android_wheels_dir):
    for wheel_name in os.listdir(dest_dir):
        if not wheel_name.endswith(".whl"):
            continue

        abi_tag = get_abi_tag(wheel_name)
        if not abi_tag:
            print(f"Could not determine ABI for {wheel_name}, skipping")
            continue

        android_wheel = find_android_wheel(android_wheels_dir, abi_tag)
        if not android_wheel:
            raise FileNotFoundError(
                f"No android wheel found for ABI {abi_tag} in {android_wheels_dir}"
            )

        kivy_wheel_path = os.path.join(dest_dir, wheel_name)

        # Collect entries from the android wheel that belong to the `android`
        # package (everything under android/ — skip dist-info).
        with zipfile.ZipFile(android_wheel, "r") as src:
            members = [
                name for name in src.namelist()
                if name.startswith("android/") and ".dist-info" not in name
            ]
            if not members:
                raise RuntimeError(
                    f"No android/ package entries found in {android_wheel}"
                )

            with zipfile.ZipFile(
                kivy_wheel_path,
                "a",
                compression=zipfile.ZIP_DEFLATED,
                compresslevel=6,
            ) as dst:
                print(f"Injecting android package into {wheel_name}:")
                for member in members:
                    data = src.read(member)
                    dst.writestr(member, data)
                    print(f"  + {member}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Inject android package from pre-built wheel into Kivy wheels."
    )
    parser.add_argument(
        "dest_dir",
        help="Directory containing the Kivy wheels to inject into.",
    )
    parser.add_argument(
        "android_wheels_dir",
        help="Directory containing the pre-built android package wheels.",
    )
    args = parser.parse_args()
    inject_android_package(args.dest_dir, args.android_wheels_dir)
