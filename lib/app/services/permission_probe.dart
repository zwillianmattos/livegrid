import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

enum AppPermission { camera, microphone, photos }

enum AppPermissionStatus { granted, pending, permanentlyDenied }

typedef PermissionStatuses = Map<AppPermission, AppPermissionStatus>;

abstract class PermissionProbe {
  Future<PermissionStatuses> check();
  Future<PermissionStatuses> request();
  Future<bool> openSettings();
}

class SystemPermissionProbe implements PermissionProbe {
  const SystemPermissionProbe();

  @override
  Future<PermissionStatuses> check() async {
    final (camera, mic, photos) = await (
      Permission.camera.status,
      Permission.microphone.status,
      _photosStatus(request: false),
    ).wait;
    return {
      AppPermission.camera: mapPermissionStatus(camera),
      AppPermission.microphone: mapPermissionStatus(mic),
      AppPermission.photos: photos,
    };
  }

  @override
  Future<PermissionStatuses> request() async {
    final needed = <Permission>[Permission.camera, Permission.microphone];
    if (Platform.isAndroid) needed.add(Permission.notification);
    final result = await needed.request();
    final photos = await _photosStatus(request: true);
    return {
      AppPermission.camera: mapPermissionStatus(result[Permission.camera]!),
      AppPermission.microphone: mapPermissionStatus(
        result[Permission.microphone]!,
      ),
      AppPermission.photos: photos,
    };
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  // Android Q+ publishes via MediaStore without a runtime permission, and the
  // pre-Q storage prompt would need the API level, which we don't query here.
  Future<AppPermissionStatus> _photosStatus({required bool request}) async {
    if (!Platform.isIOS) return AppPermissionStatus.granted;
    final p = Permission.photosAddOnly;
    return mapPermissionStatus(request ? await p.request() : await p.status);
  }
}

AppPermissionStatus mapPermissionStatus(PermissionStatus status) {
  switch (status) {
    case PermissionStatus.granted:
    case PermissionStatus.limited:
    case PermissionStatus.provisional:
      return AppPermissionStatus.granted;
    case PermissionStatus.permanentlyDenied:
    case PermissionStatus.restricted:
      return AppPermissionStatus.permanentlyDenied;
    case PermissionStatus.denied:
      return AppPermissionStatus.pending;
  }
}
