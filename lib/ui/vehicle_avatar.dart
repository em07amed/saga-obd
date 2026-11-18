import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../main.dart';
import '../vehicle.dart';
import 'brand_badge.dart';

/// The user's own picture for a vehicle, or the generic brand badge.
class VehicleAvatar extends StatelessWidget {
  final Vehicle vehicle;
  final double size;
  const VehicleAvatar(this.vehicle, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final path = App.settings.vehicleImage(vehicle.id);
    if (path != null && File(path).existsSync()) {
      return ClipOval(
        child: Image.file(File(path),
            width: size, height: size, fit: BoxFit.cover),
      );
    }
    return BrandBadge(vehicle.make, size: size);
  }
}

/// Lets the user pick a picture from the gallery and stores a copy in the
/// app's own folder (so it survives the gallery file being deleted).
Future<String?> pickVehicleImage() async {
  final x = await ImagePicker()
      .pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512);
  if (x == null) return null;
  final dir = await getApplicationDocumentsDirectory();
  final dest =
      '${dir.path}/vehicle_${DateTime.now().millisecondsSinceEpoch}.jpg';
  await File(x.path).copy(dest);
  return dest;
}
