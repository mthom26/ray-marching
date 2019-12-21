use luminance::shader::program::Uniform;
use luminance_derive::{Semantics, UniformInterface, Vertex};

#[derive(Copy, Clone, Debug, Semantics)]
pub enum Semantics {
    #[sem(name = "position", repr = "[f32; 3]", wrapper = "VertexPos")]
    Position,
}

#[repr(C)]
#[derive(Vertex)]
#[vertex(sem = "Semantics")]
pub struct Vertex {
    pub pos: VertexPos,
}

#[derive(UniformInterface)]
pub struct ShaderInterface {
    #[uniform(unbound)]
    pub time: Uniform<f32>,
    #[uniform(unbound)]
    pub cam_pos: Uniform<[f32; 3]>,
    #[uniform(unbound)]
    pub resolution: Uniform<[f32; 2]>,
}
