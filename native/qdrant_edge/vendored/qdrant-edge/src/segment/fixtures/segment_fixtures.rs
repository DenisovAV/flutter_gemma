use std::path::Path;

use crate::common::counter::hardware_counter::HardwareCounterCell;

use crate::segment::data_types::named_vectors::NamedVectors;
use crate::segment::data_types::vectors::DEFAULT_VECTOR_NAME;
use crate::segment::entry::entry_point::SegmentEntry;
use crate::segment::fixtures::index_fixtures::random_vector;
use crate::segment::fixtures::payload_fixtures::generate_diverse_payload;
use crate::segment::segment::Segment;
use crate::segment::segment_constructor::simple_segment_constructor::build_simple_segment;
use crate::segment::types::Distance;

pub fn random_segment(path: &Path, num_points: usize) -> Segment {
    let dim = 4;
    let distance = Distance::Dot;

    let mut rnd_gen = rand::rng();

    let mut segment = build_simple_segment(path, dim, distance).unwrap();

    let hw_counter = HardwareCounterCell::new();

    for point_id in 0..num_points {
        let vector = random_vector(&mut rnd_gen, dim);
        let payload = generate_diverse_payload(&mut rnd_gen);

        segment
            .upsert_point(
                100,
                (point_id as u64).into(),
                NamedVectors::from_ref(DEFAULT_VECTOR_NAME, vector.as_slice().into()),
                &hw_counter,
            )
            .unwrap();
        segment
            .set_payload(100, (point_id as u64).into(), &payload, &None, &hw_counter)
            .unwrap();
    }

    segment
}
