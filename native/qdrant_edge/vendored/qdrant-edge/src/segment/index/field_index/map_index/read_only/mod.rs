use crate::common::universal_io::UniversalRead;
use crate::gridstore::Blob;

use crate::segment::index::field_index::map_index::MapIndexKey;
use crate::segment::index::field_index::map_index::mutable_map_index::read_only::ReadOnlyAppendableMapIndex;
use crate::segment::index::field_index::map_index::universal_map_index::UniversalMapIndex;

mod read_ops;

pub enum ReadOnlyMapIndex<N: MapIndexKey + ?Sized, S: UniversalRead>
where
    Vec<<N as MapIndexKey>::Owned>: Blob + Send + Sync,
{
    /// Loads into RAM from appendable storage format
    Appendable(ReadOnlyAppendableMapIndex<N, S>),
    /// Directly reads from storage in immutable format
    Immutable(UniversalMapIndex<N, S>),
}
