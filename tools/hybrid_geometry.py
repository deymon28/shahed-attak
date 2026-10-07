"""Mechanical construction helpers for detailed, reference-style machinery."""
import math

import bpy
from mathutils import Vector

from hybrid_materials import face_uvs


OBJECTS = []


def register(obj, name, material, parent=None, bevel=0):
    obj.name = name
    if material:
        obj.data.materials.append(material)
    if parent:
        obj.parent = parent
    if bevel:
        modifier = obj.modifiers.new('Machined edge profile', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 3
        modifier = obj.modifiers.new('Weighted hard-surface normals', 'WEIGHTED_NORMAL')
        modifier.keep_sharp = True
    OBJECTS.append(obj)
    return obj


def box(name, location, size, material, parent=None, bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    face_uvs(obj.data)
    return register(obj, name, material, parent, bevel)


def cylinder(name, location, radius, depth, material, parent=None, axis=(0, 0, 1), vertices=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    obj = bpy.context.object
    obj.rotation_euler = Vector(axis).to_track_quat('Z', 'Y').to_euler()
    return register(obj, name, material, parent, min(.012, radius * .09))


def cable(name, points, radius, material, parent=None):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 12
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = point.handle_right_type = 'AUTO'
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    register(obj, name, material, parent)
    return obj


def beam(name, start, end, width, material, parent=None):
    start, end = Vector(start), Vector(end)
    obj = box(name, (start + end) / 2, (width, width, (end - start).length), material, parent, width * .15)
    obj.rotation_euler = (end - start).to_track_quat('Z', 'Y').to_euler()
    return obj


def ring(name, location, outer, inner, depth, material, parent=None, steps=64):
    vertices = []
    for z in (-depth / 2, depth / 2):
        for radius in (outer, inner):
            vertices.extend((math.sin(a * math.tau / steps) * radius,
                             math.cos(a * math.tau / steps) * radius, z) for a in range(steps))
    faces = []
    for a in range(steps):
        b = (a + 1) % steps
        faces.extend(((a, b, 2 * steps + b, 2 * steps + a),
                      (steps + b, steps + a, 3 * steps + a, 3 * steps + b),
                      (2 * steps + a, 2 * steps + b, 3 * steps + b, 3 * steps + a),
                      (b, a, steps + a, steps + b)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    return register(obj, name, material, parent, .012)


def bolted_panel(name, location, size, materials, tile='graphite', parent=None):
    box(name + ' rim', location, size, materials['steel'], parent, .035)
    x, y, z = location
    w, h, d = size
    box(name + ' inset', (x, y, z + d / 2 + .01), (w * .91, h * .91, .025), materials[tile], parent, .015)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cylinder(name + ' fastener', (x + sx * w * .39, y + sy * h * .39, z + d / 2 + .03),
                     .027, .026, materials['edge'], parent, vertices=6)


def beacon(name, location, materials, parent=None, color='amber'):
    x, y, z = location
    cylinder(name + ' socket', (x, y, z), .07, .10, materials['steel'], parent)
    cylinder(name + ' glass', (x, y, z + .085), .042, .12, materials[color], parent)
    for angle in (0, math.pi / 2, math.pi, math.pi * 1.5):
        cylinder(name + ' cage', (x + math.sin(angle) * .06, y + math.cos(angle) * .06, z + .09),
                 .007, .16, materials['edge'], parent, vertices=8)


def fan(name, location, radius, materials, rotor=None):
    ring(name + ' armored rim', location, radius, radius * .79, .10, materials['steel'])
    x, y, z = location
    cylinder(name + ' recess', (x, y, z - .02), radius * .8, .025, materials['dark'])
    rx, ry, rz = (0, 0, 0) if rotor else (x, y, z)
    if rotor:
        rotor.location = location
    for i in range(7):
        angle = i * math.tau / 7
        obj = box(name + ' vane', (rx + math.sin(angle) * radius * .40, ry + math.cos(angle) * radius * .40, rz + .03),
                  (radius * .18, radius * .65, .025), materials['edge'], rotor, .015)
        obj.rotation_euler.z = -angle + .24
    cylinder(name + ' hub', (rx, ry, rz + .05), radius * .23, .075, materials['steel'], rotor)
    for angle in (0, math.pi / 2):
        obj = box(name + ' safety bridge', (x, y, z + .095), (radius * 1.85, .025, .03), materials['steel'])
        obj.rotation_euler.z = angle
