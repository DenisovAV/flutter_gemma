//! [`PayloadFieldIndexRead`] dispatch for [`ReadOnlyNumericIndexInner`].
//!
//! The query logic is shared with the writable index via the generic
//! [`query`](super::super::super::query) helpers over [`NumericIndexRead`];
//! this impl just plugs the read-only enum into them.

use crate::common::counter::hardware_accumulator::HwMeasurementAcc;
use crate::common::counter::hardware_counter::HardwareCounterCell;
use crate::common::types::PointOffsetType;
use crate::common::universal_io::UniversalRead;
use crate::gridstore::Blob;

use super::super::super::numeric_index_read::NumericIndexRead;
use super::super::super::{Encodable, query};
use super::ReadOnlyNumericIndexInner;
use crate::segment::common::operation_error::OperationResult;
use crate::segment::index::field_index::numeric_point::Numericable;
use crate::segment::index::field_index::stored_point_to_values::StoredValue;
use crate::segment::index::field_index::{
    CardinalityEstimation, PayloadBlockCondition, PayloadFieldIndexRead,
};
use crate::segment::index::query_optimization::optimized_filter::ConditionCheckerFn;
use crate::segment::types::{FieldCondition, PayloadKeyType};

impl<T: Encodable + Numericable + StoredValue + Send + Sync + Default, S: UniversalRead>
    PayloadFieldIndexRead for ReadOnlyNumericIndexInner<T, S>
where
    Vec<T>: Blob,
{
    fn count_indexed_points(&self) -> usize {
        self.get_points_count()
    }

    fn filter<'a>(
        &'a self,
        condition: &'a FieldCondition,
        hw_counter: &'a HardwareCounterCell,
    ) -> OperationResult<Option<Box<dyn Iterator<Item = PointOffsetType> + 'a>>> {
        query::filter(self, condition, hw_counter)
    }

    fn estimate_cardinality(
        &self,
        condition: &FieldCondition,
        hw_counter: &HardwareCounterCell,
    ) -> OperationResult<Option<CardinalityEstimation>> {
        query::estimate_cardinality(self, condition, hw_counter)
    }

    fn for_each_payload_block(
        &self,
        threshold: usize,
        key: PayloadKeyType,
        f: &mut dyn FnMut(PayloadBlockCondition) -> OperationResult<()>,
    ) -> OperationResult<()> {
        query::for_each_payload_block(self, threshold, key, f)
    }

    fn condition_checker<'a>(
        &'a self,
        condition: &FieldCondition,
        hw_acc: HwMeasurementAcc,
    ) -> Option<ConditionCheckerFn<'a>> {
        query::condition_checker(self, condition, hw_acc)
    }
}
