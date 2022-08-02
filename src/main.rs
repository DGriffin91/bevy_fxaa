use bevy::{
    prelude::*,
    reflect::TypeUuid,
    render::{
        camera::{Camera, RenderTarget},
        render_resource::{
            AsBindGroup, Extent3d, ShaderRef, TextureDescriptor, TextureDimension, TextureFormat,
            TextureUsages,
        },
        view::RenderLayers,
    },
    sprite::{Material2d, Material2dPlugin, MaterialMesh2dBundle, Mesh2dHandle},
    window::WindowResized,
};

fn main() {
    let mut app = App::new();
    app.add_plugins(DefaultPlugins)
        .insert_resource(Msaa { samples: 1 })
        .add_plugin(Material2dPlugin::<PostProcessingMaterial>::default())
        .add_startup_system(setup)
        .add_system(main_camera_cube_rotator_system)
        .add_system(window_resized);

    app.run();
}

/// Marks the first camera cube (rendered to a texture.)
#[derive(Component)]
struct MainCube;

#[derive(Component)]
struct PostProcessMesh;

fn setup(
    mut commands: Commands,
    mut windows: ResMut<Windows>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut post_processing_materials: ResMut<Assets<PostProcessingMaterial>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut images: ResMut<Assets<Image>>,
) {
    let window = windows.get_primary_mut().unwrap();
    let size = Extent3d {
        width: window.physical_width(),
        height: window.physical_height(),
        ..default()
    };

    // This is the texture that will be rendered to.
    let mut image = Image {
        texture_descriptor: TextureDescriptor {
            label: None,
            size,
            dimension: TextureDimension::D2,
            format: TextureFormat::Bgra8UnormSrgb,
            mip_level_count: 1,
            sample_count: 1,
            usage: TextureUsages::TEXTURE_BINDING
                | TextureUsages::COPY_DST
                | TextureUsages::RENDER_ATTACHMENT,
        },
        ..default()
    };
    image.resize(size);

    let image_handle = images.add(image);

    let cube_handle = meshes.add(Mesh::from(shape::Cube { size: 4.0 }));
    let cube_material_handle = materials.add(StandardMaterial {
        base_color: Color::rgb(0.8, 0.7, 0.6),
        reflectance: 0.02,
        unlit: false,
        ..default()
    });

    // The cube that will be rendered to the texture.
    commands
        .spawn_bundle(PbrBundle {
            mesh: cube_handle,
            material: cube_material_handle,
            transform: Transform::from_translation(Vec3::new(0.0, 0.0, 1.0))
                .with_scale(Vec3::new(2.0, 2.0, 2.0)),
            ..default()
        })
        .insert(MainCube);

    // Light
    // NOTE: Currently lights are ignoring render layers - see https://github.com/bevyengine/bevy/issues/3462
    commands.spawn_bundle(PointLightBundle {
        transform: Transform::from_translation(Vec3::new(0.0, 0.0, 10.0)),
        ..default()
    });

    let quad_handle = meshes.add(Mesh::from(shape::Quad::new(Vec2::new(
        size.width as f32,
        size.height as f32,
    ))));

    // This material has the texture that has been rendered.
    let material_handle = post_processing_materials.add(PostProcessingMaterial {
        source_image: image_handle.clone(),
    });

    // Main camera, first to render
    commands.spawn_bundle(Camera3dBundle {
        camera: Camera {
            target: RenderTarget::Image(image_handle.clone()),
            ..default()
        },
        transform: Transform::from_translation(Vec3::new(0.0, 0.0, 15.0))
            .looking_at(Vec3::default(), Vec3::Y),
        ..default()
    });

    // This specifies the layer used for the post processing camera, which will be attached to the post processing camera and 2d quad.
    let post_processing_pass_layer = RenderLayers::layer((RenderLayers::TOTAL_LAYERS - 1) as u8);

    // Post processing 2d quad, with material using the render texture done by the main camera, with a custom shader.
    commands
        .spawn_bundle(MaterialMesh2dBundle {
            mesh: quad_handle.into(),
            material: material_handle,
            transform: Transform {
                translation: Vec3::new(0.0, 0.0, 1.5),
                ..default()
            },
            ..default()
        })
        .insert(post_processing_pass_layer)
        .insert(PostProcessMesh);

    // The post-processing pass camera.
    commands
        .spawn_bundle(Camera2dBundle {
            camera: Camera {
                // renders after the first main camera which has default value: 0.
                priority: 1,
                ..default()
            },
            ..Camera2dBundle::default()
        })
        .insert(post_processing_pass_layer);
}

/// Rotates the cube rendered by the main camera
fn main_camera_cube_rotator_system(
    time: Res<Time>,
    mut query: Query<&mut Transform, With<MainCube>>,
) {
    for mut transform in query.iter_mut() {
        transform.rotate_x(0.55 * time.delta_seconds());
        transform.rotate_z(0.15 * time.delta_seconds());
    }
}

fn window_resized(
    mut window_resized_events: EventReader<WindowResized>,
    mut post_processing_materials: ResMut<Assets<PostProcessingMaterial>>,
    mut images: ResMut<Assets<Image>>,
    mut meshes: ResMut<Assets<Mesh>>,
    post_process_mesh: Query<&Mesh2dHandle, With<PostProcessMesh>>,
    mut image_events: EventWriter<AssetEvent<Image>>,
) {
    if let Some(event) = window_resized_events.iter().last() {
        let width = event.width as u32;
        let height = event.height as u32;
        if let Some((_, mat)) = post_processing_materials.iter_mut().next() {
            let image = images.get_mut(&mat.source_image).unwrap();
            image.resize(Extent3d {
                width,
                height,
                ..default()
            });
            image_events.send(AssetEvent::Modified {
                handle: mat.source_image.clone(),
            });

            // Resize Mesh
            for mesh in post_process_mesh.iter() {
                let quad = Mesh::from(shape::Quad::new(Vec2::new(width as f32, height as f32)));
                let _ = meshes.set(mesh.0.clone(), quad);
            }
        }
    }
}

// Region below declares of the custom material handling post processing effect

/// Our custom post processing material
#[derive(AsBindGroup, TypeUuid, Clone)]
#[uuid = "bc2f08eb-a0fb-43f1-a908-54871ea597d5"]
struct PostProcessingMaterial {
    /// In this example, this image will be the result of the main camera.    
    #[texture(0)]
    #[sampler(1)]
    source_image: Handle<Image>,
}

impl Material2d for PostProcessingMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/fxaa.wgsl".into()
    }

    fn vertex_shader() -> ShaderRef {
        "shaders/fxaa.wgsl".into()
    }
}
