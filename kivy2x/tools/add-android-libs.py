import argparse
import os
import zipfile

KIVY_DEPS_ROOT = os.environ.get("KIVY_DEPS_ROOT", None)
if not KIVY_DEPS_ROOT:
    print(
        "KIVY_DEPS_ROOT environment variable is not set. "
        "Please set it to the path where Android SDL2 libraries are located."
    )
    raise EnvironmentError("KIVY_DEPS_ROOT environment variable is not set")


def get_abi_from_wheel(wheel_name):
    """Determine ABI from wheel filename platform tag."""
    if "arm64_v8a" in wheel_name or "aarch64" in wheel_name:
        return "arm64-v8a"
    elif "x86_64" in wheel_name:
        return "x86_64"
    return None


def add_android_libs_to_wheels(wheels_path: str):
    libs_base = os.path.join(KIVY_DEPS_ROOT, "dist", "libs")
    if not os.path.exists(libs_base):
        raise FileNotFoundError(
            "Android libs folder does not exist at path: {}".format(libs_base)
        )

    if not os.path.exists(wheels_path):
        raise FileNotFoundError(
            "Specified folder does not exist at path: {}".format(wheels_path)
        )

    for wheel in os.listdir(wheels_path):
        if not wheel.endswith(".whl"):
            continue

        abi = get_abi_from_wheel(wheel)
        if not abi:
            print(
                "Could not determine ABI for wheel: {}, skipping".format(wheel)
            )
            continue

        libs_dir = os.path.join(libs_base, abi)
        if not os.path.exists(libs_dir):
            raise FileNotFoundError(
                "Libs folder for ABI {} does not exist at: {}".format(
                    abi, libs_dir
                )
            )

        so_files = [f for f in os.listdir(libs_dir) if f.endswith(".so")]
        if not so_files:
            print("No .so files found in {}".format(libs_dir))
            continue

        wheel_path = os.path.join(wheels_path, wheel)
        temp_wheel = wheel_path + '.tmp'
        records = []
        record_filename = None

        def get_hash(content):
            import hashlib, base64
            digest = hashlib.sha256(content).digest()
            return 'sha256=' + base64.urlsafe_b64encode(digest).decode('ascii').rstrip('=')

        with zipfile.ZipFile(wheel_path, 'r') as zin, \
             zipfile.ZipFile(temp_wheel, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zout:

            print("Adding Android files to wheel: {}".format(wheel_path))
            
            written_files = set()
            
            # Copy existing files
            for item in zin.infolist():
                if item.filename.endswith('RECORD'):
                    record_filename = item.filename
                    continue
                # Skip existing injected folders so we can cleanly overwrite them
                if item.filename.startswith(('.java/', '.kotlin/', '.gradle/', '.include/')):
                    continue
                content = zin.read(item.filename)
                zout.writestr(item, content)
                records.append(f"{item.filename},{get_hash(content)},{len(content)}")
                written_files.add(item.filename)

            # Inject .so files
            for so_file in so_files:
                file_path = os.path.join(libs_dir, so_file)
                arcname = os.path.join(".libs", abi, so_file).replace('\\', '/')
                print("  Adding {} as {}".format(so_file, arcname))
                with open(file_path, 'rb') as f:
                    content = f.read()
                if arcname not in written_files:
                    zout.writestr(arcname, content)
                    records.append(f"{arcname},{get_hash(content)},{len(content)}")
                    written_files.add(arcname)

            # Inject SDL2 Java sources under .java/
            java_dir = os.path.join(KIVY_DEPS_ROOT, "dist", "java")
            if os.path.isdir(java_dir):
                print("Adding Android Java sources to wheel: {}".format(wheel_path))
                for root, _dirs, files in os.walk(java_dir):
                    for fname in files:
                        file_path = os.path.join(root, fname)
                        rel = os.path.relpath(file_path, java_dir)
                        arcname = os.path.join(".java", rel).replace('\\', '/')
                        print("  Adding {} as {}".format(rel, arcname))
                        with open(file_path, 'rb') as f:
                            content = f.read()
                        if arcname not in written_files:
                            zout.writestr(arcname, content)
                            records.append(f"{arcname},{get_hash(content)},{len(content)}")
                            written_files.add(arcname)
            else:
                print(
                    "No Java sources found at {}, skipping .java/ injection".format(
                        java_dir
                    )
                )

            # Inject Kivy local Java sources under .java/
            kivy_java_dir = "java"
            if os.path.isdir(kivy_java_dir):
                print("Adding Kivy local Java sources to wheel: {}".format(wheel_path))
                for root, _dirs, files in os.walk(kivy_java_dir):
                    for fname in files:
                        if not fname.endswith('.java'):
                            continue
                        file_path = os.path.join(root, fname)
                        rel = os.path.relpath(file_path, kivy_java_dir)
                        arcname = os.path.join(".java", rel).replace('\\', '/')
                        print("  Adding {} as {}".format(rel, arcname))
                        with open(file_path, 'rb') as f:
                            content = f.read()
                        if arcname not in written_files:
                            zout.writestr(arcname, content)
                            records.append(f"{arcname},{get_hash(content)},{len(content)}")
                            written_files.add(arcname)

            # Inject SDL2 Kotlin sources under .kotlin/
            kotlin_dir = os.path.join(KIVY_DEPS_ROOT, "dist", "kotlin")
            if os.path.isdir(kotlin_dir):
                print("Adding Android Kotlin sources to wheel: {}".format(wheel_path))
                for root, _dirs, files in os.walk(kotlin_dir):
                    for fname in files:
                        file_path = os.path.join(root, fname)
                        rel = os.path.relpath(file_path, kotlin_dir)
                        arcname = os.path.join(".kotlin", rel).replace('\\', '/')
                        print("  Adding {} as {}".format(rel, arcname))
                        with open(file_path, 'rb') as f:
                            content = f.read()
                        if arcname not in written_files:
                            zout.writestr(arcname, content)
                            records.append(f"{arcname},{get_hash(content)},{len(content)}")
                            written_files.add(arcname)
            else:
                print(
                    "No Kotlin sources found at {}, skipping .kotlin/ injection".format(
                        kotlin_dir
                    )
                )

            # Inject Kivy local Kotlin sources under .kotlin/
            kivy_kotlin_dir = "kotlin"
            if os.path.isdir(kivy_kotlin_dir):
                print("Adding Kivy local Kotlin sources to wheel: {}".format(wheel_path))
                for root, _dirs, files in os.walk(kivy_kotlin_dir):
                    for fname in files:
                        if not fname.endswith('.kt'):
                            continue
                        file_path = os.path.join(root, fname)
                        rel = os.path.relpath(file_path, kivy_kotlin_dir)
                        arcname = os.path.join(".kotlin", rel).replace('\\', '/')
                        print("  Adding {} as {}".format(rel, arcname))
                        with open(file_path, 'rb') as f:
                            content = f.read()
                        if arcname not in written_files:
                            zout.writestr(arcname, content)
                            records.append(f"{arcname},{get_hash(content)},{len(content)}")
                            written_files.add(arcname)

            # Inject Gradle files under .gradle/
            gradle_dir = os.path.join(KIVY_DEPS_ROOT, "dist", "gradle")
            if os.path.isdir(gradle_dir):
                print("Adding Gradle files to wheel: {}".format(wheel_path))
                for root, _dirs, files in os.walk(gradle_dir):
                    for fname in files:
                        file_path = os.path.join(root, fname)
                        rel = os.path.relpath(file_path, gradle_dir)
                        arcname = os.path.join(".gradle", rel).replace('\\', '/')
                        print("  Adding {} as {}".format(rel, arcname))
                        with open(file_path, 'rb') as f:
                            content = f.read()
                        if arcname not in written_files:
                            zout.writestr(arcname, content)
                            records.append(f"{arcname},{get_hash(content)},{len(content)}")
                            written_files.add(arcname)
            else:
                print(
                    "No Gradle files found at {}, skipping .gradle/ injection".format(
                        gradle_dir
                    )
                )

            # Inject Kivy local Gradle files under .gradle/
            kivy_gradle_dir = "gradle"
            if os.path.isdir(kivy_gradle_dir):
                print("Adding Kivy local Gradle files to wheel: {}".format(wheel_path))
                for root, _dirs, files in os.walk(kivy_gradle_dir):
                    for fname in files:
                        if not (fname.endswith('.gradle') or fname.endswith('.kts') or fname.endswith('.properties')):
                            continue
                        file_path = os.path.join(root, fname)
                        rel = os.path.relpath(file_path, kivy_gradle_dir)
                        arcname = os.path.join(".gradle", rel).replace('\\', '/')
                        print("  Adding {} as {}".format(rel, arcname))
                        with open(file_path, 'rb') as f:
                            content = f.read()
                        if arcname not in written_files:
                            zout.writestr(arcname, content)
                            records.append(f"{arcname},{get_hash(content)},{len(content)}")
                            written_files.add(arcname)

            # Inject SDL2 headers under .include/
            include_dir = os.path.join(KIVY_DEPS_ROOT, "dist", "include")
            if os.path.isdir(include_dir):
                print("Adding Android SDL headers to wheel: {}".format(wheel_path))
                for root, _dirs, files in os.walk(include_dir):
                    for fname in files:
                        file_path = os.path.join(root, fname)
                        rel = os.path.relpath(file_path, include_dir)
                        arcname = os.path.join(".include", rel).replace('\\', '/')
                        print("  Adding {} as {}".format(rel, arcname))
                        with open(file_path, 'rb') as f:
                            content = f.read()
                        if arcname not in written_files:
                            zout.writestr(arcname, content)
                            records.append(f"{arcname},{get_hash(content)},{len(content)}")
                            written_files.add(arcname)
            else:
                print(
                    "No headers found at {}, skipping .include/ injection".format(
                        include_dir
                    )
                )

            # Rewrite RECORD
            if record_filename:
                records.append(f"{record_filename},,")
                record_content = '\n'.join(records) + '\n'
                zout.writestr(record_filename, record_content.encode('utf-8'))
            
        # Replace the old wheel with the updated one
        os.remove(wheel_path)
        os.rename(temp_wheel, wheel_path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description=(
            "Add Android .so files in .libs/{ABI}/ folder "
            "to all wheels in the specified directory."
        )
    )
    parser.add_argument(
        "wheels_path",
        help=(
            "Path to the directory containing the wheels "
            "to which Android .so libraries should be added."
        ),
    )
    args = parser.parse_args()

    add_android_libs_to_wheels(args.wheels_path)
