use crate::common::counter::hardware_accumulator::HwMeasurementAcc;
use crate::common::counter::hardware_counter::HardwareCounterCell;
use crate::common::types::PointOffsetType;
use crate::common::universal_io::MmapFile;

use super::super::read_ops::{self, NullIndexRead};
use super::ImmutableNullIndex;
use crate::segment::common::flags::roaring_flags::RoaringFlags;
use crate::segment::common::operation_error::OperationResult;
use crate::segment::index::field_index::{
    CardinalityEstimation, PayloadBlockCondition, PayloadFieldIndexRead,
};
use crate::segment::index::query_optimization::optimized_filter::ConditionCheckerFn;
use crate::segment::types::{FieldCondition, PayloadKeyType};

impl NullIndexRead for ImmutableNullIndex {
    type Flags = RoaringFlags<MmapFile>;

    fn has_values_flags(&self) -> &Self::Flags {
        self.0.has_values_flags()
    }

    fn is_null_flags(&self) -> &Self::Flags {
        self.0.is_null_flags()
    }

    fn total_point_count(&self) -> usize {
        self.0.total_point_count()
    }

    fn telemetry_index_type(&self) -> &'static str {
        "immutable_null_index"
    }
}

impl PayloadFieldIndexRead for ImmutableNullIndex {
    #[inline]
    fn count_indexed_points(&self) -> usize {
        self.indexed_points_count()
    }

    #[inline]
    fn filter<'a>(
        &'a self,
        condition: &'a FieldCondition,
        _hw_counter: &'a HardwareCounterCell,
    ) -> OperationResult<Option<Box<dyn Iterator<Item = PointOffsetType> + 'a>>> {
        Ok(read_ops::filter(self, condition))
    }

    #[inline]
    fn estimate_cardinality(
        &self,
        condition: &FieldCondition,
        _hw_counter: &HardwareCounterCell,
    ) -> OperationResult<Option<CardinalityEstimation>> {
        Ok(read_ops::estimate_cardinality(self, condition))
    }

    #[inline]
    fn for_each_payload_block(
        &self,
        _threshold: usize,
        _key: PayloadKeyType,
        _f: &mut dyn FnMut(PayloadBlockCondition) -> OperationResult<()>,
    ) -> OperationResult<()> {
        // No payload blocks
        Ok(())
    }

    fn condition_checker<'a>(
        &'a self,
        condition: &FieldCondition,
        hw_acc: HwMeasurementAcc,
    ) -> Option<ConditionCheckerFn<'a>> {
        read_ops::condition_checker(self, condition, hw_acc)
    }
}
