import 'dart:io';

const _logoUrl = 'https://img.toufq.com/IMG/QNDXXLG.png';
const _logoPath = 'assets/images/QNDXXLG.png';

Future<void> main() async {
  final file = File(_logoPath);
  if (await file.exists() && await file.length() > 0) return;
  await file.parent.create(recursive: true);

  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(_logoUrl));
    request.headers
      ..set(HttpHeaders.userAgentHeader, 'QNDXX/6.6.6')
      ..set(HttpHeaders.acceptHeader, 'image/png,image/*;q=0.9,*/*;q=0.8');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'QNDXX logo download returned HTTP ' + response.statusCode.toString(),
        uri: Uri.parse(_logoUrl),
      );
    }
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    if (bytes.length < pngSignature.length) {
      throw const FormatException('QNDXX logo response is not a PNG file');
    }
    for (var i = 0; i < pngSignature.length; i++) {
      if (bytes[i] != pngSignature[i]) {
        throw const FormatException('QNDXX logo response is not a PNG file');
      }
    }
    await file.writeAsBytes(bytes, flush: true);
    await file.copy('assets/images/icon.png');
    stdout.writeln(
      'Downloaded QNDXX logo to $_logoPath (' +
          bytes.length.toString() +
          ' bytes).',
    );
  } finally {
    client.close(force: true);
  }
}
