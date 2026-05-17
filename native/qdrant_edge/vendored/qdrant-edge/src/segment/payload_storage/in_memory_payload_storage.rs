use ahash::AHashMap;
use crate::common::types::PointOffsetType;

use crate::segment::types::Payload;

/// Same as `SimplePayloadStorage` but without persistence
/// Warn: for tests only
#[derive(Debug, Default)]
pub struct InMemoryPayloadStorage {
    pub(crate) payload: AHashMap<PointOffsetType, Payload>,
}

impl InMemoryPayloadStorage {
    pub fn payload_ptr(&self, point_id: PointOffsetType) -> Option<&Payload> {
        self.payload.get(&point_id)
    }
}
