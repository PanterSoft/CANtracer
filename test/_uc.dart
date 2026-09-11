import 'package:cantracer/src/update.dart';
void main() async {
  print('flutter/flutter -> ${await checkForUpdate(repo: 'flutter/flutter')}');
  print('own repo        -> ${await checkForUpdate()}');
}
