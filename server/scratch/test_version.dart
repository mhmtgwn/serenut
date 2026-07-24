bool isVersionOlder(String current, String required) {
  try {
    final partsCurrent = current.split('+');
    final partsReq = required.split('+');

    final verCurrent = partsCurrent[0].split('.').map(int.parse).toList();
    final verReq = partsReq[0].split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      if (verCurrent[i] < verReq[i]) return true;
      if (verCurrent[i] > verReq[i]) return false;
    }

    if (partsCurrent.length > 1 && partsReq.length > 1) {
      final buildCurrent = int.parse(partsCurrent[1]);
      final buildReq = int.parse(partsReq[1]);
      return buildCurrent < buildReq;
    }
    return false;
  } catch (e) {
    print('Error: $e');
    return false;
  }
}

void main() {
  print('isVersionOlder("1.0.1+2", "1.0.1") = ${isVersionOlder("1.0.1+2", "1.0.1")}');
}
