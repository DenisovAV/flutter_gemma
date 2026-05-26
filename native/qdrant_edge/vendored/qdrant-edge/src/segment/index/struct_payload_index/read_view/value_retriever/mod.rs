mod helpers;

use std::collections::{HashMap, HashSet};

use crate::common::counter::hardware_counter::HardwareCounterCell;

use self::helpers::variable_retriever;
use super::StructPayloadIndexReadView;
use crate::segment::id_tracker::IdTrackerRead;
use crate::segment::index::field_index::FieldIndexRead;
use crate::segment::index::query_optimization::payload_provider::PayloadProvider;
use crate::segment::index::query_optimization::rescore_formula::value_retriever::VariableRetrieverFn;
use crate::segment::json_path::JsonPath;
use crate::segment::payload_storage::PayloadStorageRead;
use crate::segment::vector_storage::VectorStorageRead;

impl<'a, P, I, V, F> StructPayloadIndexReadView<'a, P, I, V, F>
where
    P: PayloadStorageRead,
    I: IdTrackerRead,
    V: VectorStorageRead,
    F: FieldIndexRead,
{
    /// Prepares optimized functions to extract each of the variables, given a point id.
    pub(crate) fn retrievers_map<'b, 'q>(
        &'b self,
        variables: HashSet<JsonPath>,
        hw_counter: &'q HardwareCounterCell,
    ) -> HashMap<JsonPath, VariableRetrieverFn<'q>>
    where
        'b: 'q,
    {
        let payload_provider = PayloadProvider::new(self.payload.clone());

        // prepare extraction of the variables from field indices or payload.
        let mut var_retrievers = HashMap::new();
        for key in variables {
            let payload_provider = payload_provider.clone();

            let retriever = variable_retriever(
                self.field_indexes,
                &key,
                payload_provider.clone(),
                hw_counter,
            );

            var_retrievers.insert(key, retriever);
        }

        var_retrievers
    }
}
