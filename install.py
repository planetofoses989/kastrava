#!/usr/bin/env python3
import os, sys, shutil, stat, subprocess, zipfile, io, platform

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RELEASE_ZIP = os.path.join(SCRIPT_DIR, 'Kastrava-release.zip')
PASSWORD = b'kastra27#secure!rel'
APP_NAME = 'Kastrava'
ELECTRON_BIN = None
INSTALL_DIR = '/opt/kastrava'
LAUNCHER_PATH = '/opt/kastrava/kastrava'
DESKTOP_PATH = '/usr/share/applications/kastrava.desktop'
ICON_PATH = '/usr/share/icons/hicolor/256x256/apps/kastrava.png'


def log(msg): print(f'[{APP_NAME}] {msg}')
def err(msg): print(f'[ERROR] {msg}', file=sys.stderr)


def get_version():
    try:
        import json
        with open(os.path.join(SCRIPT_DIR, 'package.json')) as f:
            return json.load(f).get('version', '')
    except Exception:
        return ''


def xor_unscramble(data, key):
    return bytes(data[i] ^ key[i % len(key)] for i in range(len(data)))


def detect_os():
    if os.path.exists('/etc/debian_version'):
        return 'debian'
    if os.path.exists('/etc/fedora-release'):
        return 'fedora'
    if os.path.exists('/etc/arch-release'):
        return 'arch'
    if os.path.exists('/etc/os-release'):
        with open('/etc/os-release') as f:
            c = f.read()
            if 'ID=arch' in c or 'ID_LIKE=arch' in c:
                return 'arch'
            if 'ID=debian' in c or 'ID_LIKE=debian' in c or 'ID=ubuntu' in c or 'ID=linuxmint' in c:
                return 'debian'
            if 'ID=fedora' in c or 'ID_LIKE=fedora' in c or 'ID=rhel' in c or 'ID=centos' in c:
                return 'fedora'
    return None


def ensure_runtime():
    global ELECTRON_BIN
    e = shutil.which('electron')
    if e:
        ELECTRON_BIN = e
        log('Electron found at ' + ELECTRON_BIN)
        return
    if shutil.which('node') and shutil.which('npm'):
        log('Node.js found, installing Electron via npm...')
        subprocess.run(['npm', 'install', '-g', 'electron', '--no-audit', '--no-fund'],
                       check=True)
        e = shutil.which('electron')
        ELECTRON_BIN = e if e else '/usr/local/bin/electron'
        log('Electron installed globally')
        return
    os_name = detect_os()
    if not os_name:
        err('Could not detect OS. Install Node.js manually then re-run.')
        sys.exit(1)
    log('Installing Node.js for ' + os_name + ' ...')
    cmds = {
        'debian': ['apt', 'install', '-y', 'nodejs', 'npm'],
        'fedora': ['dnf', 'install', '-y', 'nodejs', 'npm'],
        'arch': ['pacman', '-S', '--noconfirm', 'nodejs', 'npm']
    }
    subprocess.run(cmds[os_name], check=True)
    log('Node.js installed')
    subprocess.run(['npm', 'install', '-g', 'electron', '--no-audit', '--no-fund'],
                   check=True)
    e = shutil.which('electron')
    ELECTRON_BIN = e if e else '/usr/local/bin/electron'
    log('Electron installed globally')


def extract_release():
    log('Unlocking ' + RELEASE_ZIP + ' ...')
    try:
        with open(RELEASE_ZIP, 'rb') as f:
            scrambled = f.read()
        raw = xor_unscramble(scrambled, PASSWORD)
        with zipfile.ZipFile(io.BytesIO(raw), 'r') as zf:
            zf.extractall(INSTALL_DIR)
        log('Extracted to ' + INSTALL_DIR)
    except Exception as e:
        err('Failed to extract: ' + str(e))
        sys.exit(1)


def create_launcher():
    content = '#!/bin/sh\nexec ' + ELECTRON_BIN + ' ' + INSTALL_DIR + '\n'
    with open(LAUNCHER_PATH, 'w') as f:
        f.write(content)
    os.chmod(LAUNCHER_PATH, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
    log('Created launcher: ' + LAUNCHER_PATH)


def install_icon():
    src = os.path.join(INSTALL_DIR, 'dist', 'logo.png')
    if not os.path.exists(src):
        src = os.path.join(INSTALL_DIR, 'logo.png')
    if os.path.exists(src):
        os.makedirs(os.path.dirname(ICON_PATH), exist_ok=True)
        shutil.copy2(src, ICON_PATH)
        subprocess.run(['gtk-update-icon-cache', '-f', '-t', '/usr/share/icons/hicolor'],
                       capture_output=True)
        log('Installed icon')


def create_desktop():
    os.makedirs(os.path.dirname(DESKTOP_PATH), exist_ok=True)
    content = '''[Desktop Entry]
Version=1.0
Type=Application
Name=Kastrava
Comment=Privacy-first browser
Exec={launcher}
Icon=/usr/share/icons/hicolor/256x256/apps/kastrava.png
Terminal=false
Categories=Network;WebBrowser;
StartupWMClass=Kastrava
MimeType=x-scheme-handler/http;x-scheme-handler/https;
'''.format(launcher=LAUNCHER_PATH)
    with open(DESKTOP_PATH, 'w') as f:
        f.write(content)
    log('Created desktop entry: ' + DESKTOP_PATH)


def main():
    if os.geteuid() != 0:
        print('This installer needs root. Run: sudo python3 install.py')
        sys.exit(1)

    if not os.path.exists(RELEASE_ZIP):
        err(RELEASE_ZIP + ' not found in current directory')
        sys.exit(1)

    print()
    print('\u2554' + '\u2550' * 38 + '\u2557')
    print('\u2551' + ('Kastrava ' + get_version() + ' Installer').center(38) + '\u2551')
    print('\u255a' + '\u2550' * 38 + '\u255d')
    print()
    log('Platform: ' + platform.system() + ' ' + platform.machine())

    ensure_runtime()

    if os.path.exists(INSTALL_DIR):
        log('Removing previous installation...')
        shutil.rmtree(INSTALL_DIR)
    os.makedirs(INSTALL_DIR, exist_ok=True)

    extract_release()
    create_launcher()
    install_icon()
    create_desktop()

    print()
    log('Installation complete! Starting Kastrava...')
    subprocess.Popen([LAUNCHER_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
