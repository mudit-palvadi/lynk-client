import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../features/file_transfer/data/datasources/sender_session_remote_data_source.dart';
import '../../features/file_transfer/data/datasources/sender_session_remote_data_source_impl.dart';
import '../../features/file_transfer/data/datasources/transfer_remote_data_source.dart';
import '../../features/file_transfer/data/datasources/transfer_remote_data_source_impl.dart';
import '../../features/file_transfer/data/repositories/transfer_repository_impl.dart';
import '../../features/file_transfer/domain/repositories/transfer_repository.dart';
import '../network/network_providers.dart';

part 'transfer_providers.g.dart';

@riverpod
SenderSessionRemoteDataSource senderSessionRemoteDataSource(Ref ref) {
  final dio = ref.watch(dioProvider);
  return SenderSessionRemoteDataSourceImpl(dio: dio);
}

@riverpod
TransferRemoteDataSource transferRemoteDataSource(Ref ref) {
  final dio = ref.watch(dioProvider);
  return TransferRemoteDataSourceImpl(dio: dio);
}

@riverpod
TransferRepository transferRepository(Ref ref) {
  final remoteDataSource = ref.watch(transferRemoteDataSourceProvider);
  return TransferRepositoryImpl(remoteDataSource: remoteDataSource);
}
