use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::LazyLock;

/// 2D Vector representation matching Roblox `Vector2.new(x, y)`.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Vector2 {
    pub x: f32,
    pub y: f32,
}

impl Vector2 {
    pub fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }
}

/// RGB Color representation matching Roblox `Color3.new(r, g, b)`.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Color3 {
    pub r: f32,
    pub g: f32,
    pub b: f32,
}

impl Color3 {
    pub fn new(r: f32, g: f32, b: f32) -> Self {
        Self { r, g, b }
    }

    pub fn from_rgb(r: u8, g: u8, b: u8) -> Self {
        Self {
            r: r as f32 / 255.0,
            g: g as f32 / 255.0,
            b: b as f32 / 255.0,
        }
    }
}

/// Base properties common to all 2D drawing objects.
#[derive(Debug, Clone, PartialEq)]
pub struct BaseDrawing {
    pub visible: bool,
    pub z_index: i32,
    pub transparency: f32,
    pub color: Color3,
}

impl Default for BaseDrawing {
    fn default() -> Self {
        Self {
            visible: true,
            z_index: 1,
            transparency: 1.0,
            color: Color3::new(1.0, 1.0, 1.0),
        }
    }
}

/// 2D Line primitive.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Line {
    pub base: BaseDrawing,
    pub from: Vector2,
    pub to: Vector2,
    pub thickness: f32,
}

/// 2D Text primitive.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Text {
    pub base: BaseDrawing,
    pub text: String,
    pub position: Vector2,
    pub size: f32,
    pub center: bool,
    pub outline: bool,
    pub outline_color: Color3,
    pub font: i32,
}

/// 2D Square / Rectangle primitive.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Square {
    pub base: BaseDrawing,
    pub position: Vector2,
    pub size: Vector2,
    pub filled: bool,
    pub thickness: f32,
}

/// 2D Circle primitive.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Circle {
    pub base: BaseDrawing,
    pub position: Vector2,
    pub radius: f32,
    pub num_sides: i32,
    pub filled: bool,
    pub thickness: f32,
}

/// 2D Triangle primitive.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Triangle {
    pub base: BaseDrawing,
    pub point_a: Vector2,
    pub point_b: Vector2,
    pub point_c: Vector2,
    pub filled: bool,
    pub thickness: f32,
}

/// Supported 2D drawing primitives in Rux.
#[derive(Debug, Clone, PartialEq)]
pub enum DrawingObject {
    Line(Line),
    Text(Text),
    Square(Square),
    Circle(Circle),
    Triangle(Triangle),
}

static REGISTRY: LazyLock<DrawingRegistry> = LazyLock::new(DrawingRegistry::new);

/// Thread-safe registry storing all currently active drawing objects.
#[derive(Debug)]
pub struct DrawingRegistry {
    objects: RwLock<HashMap<u64, DrawingObject>>,
    next_id: AtomicU64,
}

impl Default for DrawingRegistry {
    fn default() -> Self {
        Self::new()
    }
}

impl DrawingRegistry {
    pub fn new() -> Self {
        Self {
            objects: RwLock::new(HashMap::new()),
            next_id: AtomicU64::new(1),
        }
    }

    pub fn global() -> &'static DrawingRegistry {
        &REGISTRY
    }

    pub fn add(&self, object: DrawingObject) -> u64 {
        // Relaxed: IDs only require uniqueness, no ordering with other atomics.
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        self.objects.write().insert(id, object);
        id
    }

    pub fn remove(&self, id: u64) -> Option<DrawingObject> {
        self.objects.write().remove(&id)
    }

    pub fn clear(&self) {
        self.objects.write().clear();
    }

    pub fn count(&self) -> usize {
        self.objects.read().len()
    }
}

/// Luau source code for the client-side Drawing API.
pub const DRAWING_LIB_SCRIPT: &str = r#"
local DrawingLib = {}
local Camera = workspace.CurrentCamera

DrawingLib.Fonts = {
    UI = 0,
    System = 1,
    Plex = 2,
    Monospace = 3
}

return DrawingLib
"#;

/// Dynamically retrieve the drawing library script.
pub fn get_drawing_lib_script() -> String {
    if let Some(custom) = crate::settings::SettingsStore::global().get_string("drawingLibScript") {
        if !custom.trim().is_empty() {
            return custom;
        }
    }
    DRAWING_LIB_SCRIPT.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_drawing_registry() {
        let registry = DrawingRegistry::new();
        let line = DrawingObject::Line(Line {
            from: Vector2::new(0.0, 0.0),
            to: Vector2::new(100.0, 100.0),
            thickness: 2.0,
            ..Default::default()
        });

        let id = registry.add(line);
        assert_eq!(registry.count(), 1);

        let removed = registry.remove(id);
        assert!(removed.is_some());
        assert_eq!(registry.count(), 0);
    }
}
