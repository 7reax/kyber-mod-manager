import 'dynamic_env_platform_interface.dart';

class DynamicEnv {
  Future<void> setEnv(String proccessName, String name, String value) async {
    return DynamicEnvPlatform.instance.setEnv(proccessName, name, value);
  }
}
