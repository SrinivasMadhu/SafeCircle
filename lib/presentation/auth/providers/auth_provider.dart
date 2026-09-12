import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final authStateProvider = StreamProvider<UserModel?>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.authStateChanges;
});

class AuthController extends StateNotifier<AsyncValue<UserModel?>> {
  final AuthRepository _repository;

  AuthController(this._repository) : super(const AsyncValue.data(null));

  Future<UserModel?> signInWithGoogle({String? customEmail, String? customName}) async {
    state = const AsyncValue.loading();
    UserModel? user;
    state = await AsyncValue.guard(() async {
      user = await _repository.signInWithGoogle(
        customEmail: customEmail,
        customName: customName,
      );
      return user;
    });
    return user;
  }

  Future<UserModel?> signInWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    UserModel? user;
    state = await AsyncValue.guard(() async {
      user = await _repository.signInWithEmail(email, password);
      return user;
    });
    return user;
  }

  Future<UserModel?> signUpWithEmail(String email, String password, String displayName) async {
    state = const AsyncValue.loading();
    UserModel? user;
    state = await AsyncValue.guard(() async {
      user = await _repository.signUpWithEmail(email, password, displayName);
      return user;
    });
    return user;
  }

  Future<UserModel?> signInDemo() async {
    state = const AsyncValue.loading();
    UserModel? user;
    state = await AsyncValue.guard(() async {
      user = await _repository.signInDemoUser();
      return user;
    });
    return user;
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    await _repository.signOut();
    state = const AsyncValue.data(null);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<UserModel?>>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthController(repository);
});
