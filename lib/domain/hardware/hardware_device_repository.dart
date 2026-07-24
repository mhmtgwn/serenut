import 'hardware_device.dart';

abstract interface class HardwareDeviceRepository {
  Future<List<HardwareDevice>> getAll();
  Future<void> save(HardwareDevice device);
  Future<void> delete(String id);
}
