import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:immich_mobile/domain/models/asset.model.dart';
import 'package:immich_mobile/domain/models/render_list.model.dart';
import 'package:immich_mobile/domain/utils/renderlist_providers.dart';
import 'package:immich_mobile/utils/constants/globals.dart';

class AssetGridState {
  final bool isDragScrolling;
  final RenderList renderList;

  const AssetGridState({
    required this.isDragScrolling,
    required this.renderList,
  });

  factory AssetGridState.empty() =>
      AssetGridState(isDragScrolling: false, renderList: RenderList.empty());

  AssetGridState copyWith({bool? isDragScrolling, RenderList? renderList}) {
    return AssetGridState(
      isDragScrolling: isDragScrolling ?? this.isDragScrolling,
      renderList: renderList ?? this.renderList,
    );
  }

  @override
  bool operator ==(covariant AssetGridState other) {
    if (identical(this, other)) return true;

    return other.renderList == renderList &&
        other.isDragScrolling == isDragScrolling;
  }

  @override
  int get hashCode => renderList.hashCode ^ isDragScrolling.hashCode;
}

class AssetGridCubit extends Cubit<AssetGridState> {
  final RenderListProvider _renderListProvider;
  late final StreamSubscription _renderListSubscription;

  /// offset of the assets from last section in [_buf]
  int _bufOffset = 0;

  /// assets cache loaded from DB with offset [_bufOffset]
  List<Asset> _buf = [];

  AssetGridCubit({required RenderListProvider renderListProvider})
      : _renderListProvider = renderListProvider,
        super(AssetGridState.empty()) {
    _renderListSubscription =
        _renderListProvider.renderStreamProvider().listen((renderList) {
      if (renderList == state.renderList) {
        return;
      }
      _bufOffset = 0;
      _buf = [];
      emit(state.copyWith(renderList: renderList));
    });
  }

  void setDragScrolling(bool isScrolling) {
    if (state.isDragScrolling != isScrolling) {
      emit(state.copyWith(isDragScrolling: isScrolling));
    }
  }

  /// Loads the requested assets from the database to an internal buffer if not cached
  /// and returns a slice of that buffer
  Future<List<Asset>> loadAssets(int offset, int count) async {
    assert(offset >= 0);
    assert(count > 0);
    assert(offset + count <= state.renderList.totalCount);

    // the requested slice (offset:offset+count) is not contained in the cache buffer `_buf`
    // thus, fill the buffer with a new batch of assets that at least contains the requested
    // assets and some more
    if (offset < _bufOffset || offset + count > _bufOffset + _buf.length) {
      final bool forward = _bufOffset < offset;

      // make sure to load a meaningful amount of data (and not only the requested slice)
      // otherwise, each call to [loadAssets] would result in DB call trashing performance
      // fills small requests to [batchSize], adds some legroom into the opposite scroll direction for large requests
      final len =
          math.max(kRenderListBatchSize, count + kRenderListOppositeBatchSize);

      // when scrolling forward, start shortly before the requested offset...
      // when scrolling backward, end shortly after the requested offset...
      // ... to guard against the user scrolling in the other direction
      // a tiny bit resulting in a another required load from the DB
      final start = math.max(
        0,
        forward
            ? offset - kRenderListOppositeBatchSize
            : (len > kRenderListBatchSize ? offset : offset + count - len),
      );

      // load the calculated batch (start:start+len) from the DB and put it into the buffer
      _buf = await _renderListProvider.renderAssetProvider(
        limit: len,
        offset: start,
      );
      _bufOffset = start;

      assert(_bufOffset <= offset);
      assert(_bufOffset + _buf.length >= offset + count);
    }

    // return the requested slice from the buffer (we made sure before that the assets are loaded!)
    return _buf.slice(offset - _bufOffset, offset - _bufOffset + count);
  }

  @override
  Future<void> close() {
    _renderListSubscription.cancel();
    return super.close();
  }
}
