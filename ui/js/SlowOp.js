.pragma library

// The late reply closes exactly what the in-time reply would close.
function closesRename(request, path) {
    return !!request && path === request.destination
}
