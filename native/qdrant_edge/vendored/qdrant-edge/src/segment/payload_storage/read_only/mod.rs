mod payload_storage_read;

use crate::common::universal_io::UniversalRead;
use crate::gridstore::GridstoreReader;

use crate::segment::types::Payload;

pub struct ReadOnlyPayloadStorage<S: UniversalRead> {
    storage: GridstoreReader<Payload, S>,
    populate: bool,
}
