import os, re
p = 'android/app/src/main/AndroidManifest.xml'
s = open(p, encoding='utf-8').read()

perms = ['INTERNET', 'CAMERA', 'RECORD_AUDIO', 'MODIFY_AUDIO_SETTINGS',
         'ACCESS_NETWORK_STATE', 'ACCESS_WIFI_STATE', 'CHANGE_NETWORK_STATE',
         'CHANGE_WIFI_MULTICAST_STATE', 'BLUETOOTH', 'BLUETOOTH_CONNECT',
         'WAKE_LOCK', 'VIBRATE']
add = ''.join(f'    <uses-permission android:name="android.permission.{x}"/>\n' for x in perms)
add += '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n'
s = s.replace('<application', add + '    <application', 1)
s = s.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="HotspotLink"', s, count=1)

# Black-screen fix: Impeller (Vulkan) renders nothing on many phones -> use the old renderer / GLES
meta = ('\n        <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false"/>'
        '\n        <meta-data android:name="io.flutter.embedding.android.ImpellerBackend" android:value="opengles"/>')
m = re.search(r'<application[^>]*>', s)
s = s[:m.end()] + meta + s[m.end():]
open(p, 'w', encoding='utf-8').write(s)

# record / webrtc need minSdk >= 23
for g in ['android/app/build.gradle.kts', 'android/app/build.gradle']:
    if os.path.exists(g):
        t = open(g, encoding='utf-8').read()
        t = t.replace('flutter.minSdkVersion', '24')
        open(g, 'w', encoding='utf-8').write(t)
print(open(p, encoding='utf-8').read())
