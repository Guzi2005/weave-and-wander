"""Project-local, hash-checked paths for isolated wearing experiments."""

import hashlib
from pathlib import Path


def project_file(root, reference):
    root = Path(root).resolve()
    reference = str(reference).strip().replace('\\', '/')
    if reference.startswith('res://'):
        reference = reference[6:]
    elif '://' in reference:
        raise ValueError('Only project-local or res:// paths are supported')
    if not reference:
        raise ValueError('Missing project-local path')
    candidate = Path(reference)
    if not candidate.is_absolute():
        candidate = root / candidate
    candidate = candidate.resolve()
    if not candidate.is_relative_to(root):
        raise ValueError('Path is outside the active project; rebind explicitly')
    return candidate


def checked_input(root, reference, expected_sha256=None):
    path = project_file(root, reference)
    if not path.is_file():
        raise ValueError('Missing experiment input: ' + str(path))
    if expected_sha256 is not None:
        expected = str(expected_sha256).lower()
        if len(expected) != 64 or any(c not in '0123456789abcdef' for c in expected):
            raise ValueError('Missing or invalid input SHA256')
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Experiment input SHA256 mismatch: ' + str(path))
    return path


def portable_reference(root, path):
    return 'res://' + project_file(root, path).relative_to(Path(root).resolve()).as_posix()


def checked_output(root, source, tag):
    if not isinstance(tag, str) or not tag.replace('_', '').isalnum():
        raise ValueError('Expected an alphanumeric output tag')
    source = project_file(root, source)
    output = project_file(root, source.with_name(source.stem + '_blender_' + tag + '.json'))
    if not output.is_relative_to(Path(root).resolve() / 'captures'):
        raise ValueError('Experiment output must remain inside project captures')
    return output


def scene_inputs(root, scene):
    source = checked_input(root, scene['source'], scene['source_sha256'])
    support = None
    if scene.get('support_source'):
        support = checked_input(root, scene['support_source'], scene.get('support_sha256', ''))
    return source, support


def rebind_inputs(root, scene, source, support_source=None):
    # Validate every dependency before changing any scene property.
    source = checked_input(root, source, scene['source_sha256'])
    support = None
    if scene.get('support_source'):
        if support_source is None:
            raise ValueError('The existing cushion also needs an explicit new path')
        support = checked_input(root, support_source, scene.get('support_sha256', ''))
    elif support_source is not None:
        raise ValueError('Cannot add a new collider to an already simulated scene')
    scene['source'] = portable_reference(root, source)
    if support:
        scene['support_source'] = portable_reference(root, support)
    return source, support
