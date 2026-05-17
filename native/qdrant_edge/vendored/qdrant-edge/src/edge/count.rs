use std::sync::atomic::AtomicBool;

use crate::common::counter::hardware_counter::HardwareCounterCell;
use crate::common::types::DeferredBehavior;
use itertools::Itertools as _;
use crate::segment::common::operation_error::OperationResult;
use crate::segment::index::field_index::EstimationMerge;
use crate::shard::count::CountRequestInternal;

use super::EdgeShard;

impl EdgeShard {
    pub fn count(&self, request: CountRequestInternal) -> OperationResult<usize> {
        let CountRequestInternal { filter, exact } = request;

        let (non_appendable, appendable) = self.segments.read().split_segments();
        let segments = non_appendable.into_iter().chain(appendable);

        let points_count = if exact {
            segments
                .map(|segment| {
                    segment.get().read().read_filtered(
                        None,
                        None,
                        filter.as_ref(),
                        &AtomicBool::new(false),
                        &HardwareCounterCell::disposable(),
                        DeferredBehavior::Exclude,
                    )
                })
                .process_results(|iter| iter.flatten().count())?
        } else {
            let cardinality = segments
                .map(|segment| {
                    segment
                        .get()
                        .read() // blocking sync lock
                        .estimate_point_count(filter.as_ref(), &HardwareCounterCell::disposable())
                })
                .process_results(|iter| iter.merge_independent())?;

            cardinality.exp
        };

        Ok(points_count)
    }
}
