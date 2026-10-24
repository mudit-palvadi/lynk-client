import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../features/file_receive/data/datasources/code_session_remote_data_source.dart';
import '../../features/file_receive/data/datasources/code_session_remote_data_source_impl.dart';
import '../../features/file_receive/data/datasources/receiver_remote_data_source.dart';
import '../../features/file_receive/data/datasources/receiver_remote_data_source_impl.dart';
import '../../features/file_receive/data/repositories/receiver_repository_impl.dart';
import '../../features/file_receive/domain/repositories/receiver_repository.dart';
import '../network/network_providers.dart';

part 'receiver_providers.g.dart';

@riverpod
ReceiverRemoteDataSource receiverRemoteDataSource(Ref ref) {
  final dio = ref.watch(dioProvider);
  return ReceiverRemoteDataSourceImpl(dio: dio);
}

@riverpod
CodeSessionRemoteDataSource codeSessionRemoteDataSource(Ref ref) {
  final dio = ref.watch(dioProvider);
  return CodeSessionRemoteDataSourceImpl(dio: dio);
}

@riverpod
ReceiverRepository receiverRepository(Ref ref) {
  final dio = ref.watch(dioProvider);
  final remoteDataSource = ReceiverRemoteDataSourceImpl(dio: dio);
  return ReceiverRepositoryImpl(remoteDataSource: remoteDataSource);
}
