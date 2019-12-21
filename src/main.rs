use std::time::Instant;

use luminance::{
    context::GraphicsContext,
    render_state::RenderState,
    shader::program::Program,
    tess::{Mode, TessBuilder},
};
use luminance_glutin::{
    ElementState, Event, GlutinSurface, KeyboardInput, Surface, VirtualKeyCode, WindowDim,
    WindowEvent, WindowOpt,
};

mod rendering;
use rendering::{Semantics, ShaderInterface, Vertex, VertexPos};

const WIDTH: u32 = 1280;
const HEIGHT: u32 = 720;

const VS: &str = include_str!("shaders/vertex.glsl");
const FS: &str = include_str!("shaders/fragment.glsl");

fn main() {
    let mut surface = GlutinSurface::new(
        WindowDim::Windowed(WIDTH, HEIGHT),
        "Ray Marching",
        WindowOpt::default(),
    )
    .expect("Could not create GLUTIN surface.");

    let back_buffer = surface.back_buffer().unwrap();

    // Shader Programs
    let program: Program<Semantics, (), ShaderInterface> =
        Program::from_strings(None, VS, None, FS)
            .expect("Could not create program.")
            .ignore_warnings();

    let vertices = [
        Vertex {
            pos: VertexPos::new([-1.0, -1.0, 0.0]),
        },
        Vertex {
            pos: VertexPos::new([1.0, -1.0, 0.0]),
        },
        Vertex {
            pos: VertexPos::new([1.0, 1.0, 0.0]),
        },
        Vertex {
            pos: VertexPos::new([-1.0, 1.0, 0.0]),
        },
    ];

    let quad = TessBuilder::new(&mut surface)
        .add_vertices(vertices)
        .set_mode(Mode::TriangleFan)
        .build()
        .unwrap();

    let t_start = Instant::now();

    'app: loop {
        // Input
        for event in surface.poll_events() {
            if let Event::WindowEvent { event, .. } = event {
                match event {
                    // Close the window
                    WindowEvent::CloseRequested
                    | WindowEvent::Destroyed
                    | WindowEvent::KeyboardInput {
                        input:
                            KeyboardInput {
                                state: ElementState::Released,
                                virtual_keycode: Some(VirtualKeyCode::Escape),
                                ..
                            },
                        ..
                    } => break 'app,
                    _ => (),
                }
            }
        }

        // State
        let clear_color = [0.2, 0.2, 0.2, 1.0];

        let t = t_start.elapsed().as_millis() as f32 / 1000.0;

        let (cam_x, cam_y, cam_z) = (8.0, 5.0, 7.0);

        // Rendering
        surface
            .pipeline_builder()
            .pipeline(&back_buffer, clear_color, |_, mut shd_gate| {
                shd_gate.shade(&program, |iface, mut rdr_gate| {
                    iface.time.update(t);
                    iface.cam_pos.update([cam_x, cam_y, cam_z]);
                    iface.resolution.update([WIDTH as f32, HEIGHT as f32]);

                    rdr_gate.render(RenderState::default(), |mut tess_gate| {
                        tess_gate.render(&quad);
                    });
                });
            });

        surface.swap_buffers();
    }
}
