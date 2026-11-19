const stSending = 0, stSent = 1, stDelivered = 2;
const dlNone = 0, dlLoading = 1, dlDone = 2, dlFailed = 3;

String hm(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}

String kindOf(String name) {
  final e = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(e)) return 'image';
  if (['mp4', 'mkv', '3gp', 'webm', 'mov', 'avi'].contains(e)) return 'video';
  if (['mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac'].contains(e)) return 'audio';
  return 'file';
}

/// kind: text | image | video | audio | voice | file | sys
class Msg {
  final String id, thread, from, fromName, kind;
  final bool mine;
  final String text;
  final String? fid, name;
  String? path;
  final int size, ts;
  int status, dl;
  double progress = 0;

  Msg({
    required this.id,
    required this.thread,
    required this.from,
    required this.fromName,
    required this.kind,
    required this.mine,
    this.text = '',
    this.fid,
    this.name,
    this.path,
    this.size = 0,
    required this.ts,
    this.status = stSending,
    this.dl = dlNone,
  });

  bool get isFile => fid != null;

  Map<String, dynamic> toJson() => {
        'id': id, 'thread': thread, 'from': from, 'fromName': fromName, 'kind': kind,
        'mine': mine, 'text': text, 'fid': fid, 'name': name, 'path': path,
        'size': size, 'ts': ts, 'status': status, 'dl': dl,
      };

  factory Msg.fromJson(Map j) => Msg(
        id: j['id'], thread: j['thread'], from: j['from'], fromName: j['fromName'] ?? '',
        kind: j['kind'], mine: j['mine'] == true, text: j['text'] ?? '',
        fid: j['fid'], name: j['name'], path: j['path'], size: j['size'] ?? 0,
        ts: j['ts'], status: j['status'] ?? stSent,
        dl: _dlFix(j),
      );
}

int _dlFix(Map j) {
  final d = (j['dl'] ?? 0) as int;
  if (d == dlLoading) return dlFailed;
  if (j['fid'] != null && j['mine'] != true && d != dlDone) return dlFailed;
  return d;
}

String previewOf(Msg m) {
  switch (m.kind) {
    case 'image': return '📷 ছবি';
    case 'video': return '🎥 ভিডিও';
    case 'audio': return '🎵 অডিও';
    case 'voice': return '🎤 ভয়েস মেসেজ';
    case 'file': return '📎 ${m.name ?? 'ফাইল'}';
    default: return m.text;
  }
}

class Group {
  final String gid;
  String name;
  List<String> members;
  Group(this.gid, this.name, this.members);
  Map<String, dynamic> toJson() => {'gid': gid, 'name': name, 'members': members};
  factory Group.fromJson(Map j) =>
      Group(j['gid'], j['name'], List<String>.from(j['members'] ?? []));
}
