use crate::common::types::PointOffsetType;
use serde_json::Value;

use crate::segment::common::utils::MultiValue;

pub type VariableRetrieverFn<'a> = Box<dyn Fn(PointOffsetType) -> MultiValue<Value> + 'a>;
