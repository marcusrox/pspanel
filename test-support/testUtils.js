const path = require('path');

function getRouteHandler(router, method, routePath) {
    const normalizedMethod = method.toLowerCase();
    const layer = router.stack.find((candidate) => (
        candidate.route
        && candidate.route.path === routePath
        && candidate.route.methods[normalizedMethod]
    ));

    if (!layer) {
        throw new Error(`Rota nao encontrada: ${method.toUpperCase()} ${routePath}`);
    }

    const handlers = layer.route.stack
        .filter((candidate) => candidate.method === normalizedMethod)
        .map((candidate) => candidate.handle);
    return handlers[handlers.length - 1];
}

function createResponse() {
    let finish;
    const done = new Promise((resolve) => {
        finish = resolve;
    });

    const response = {
        statusCode: 200,
        headers: {},
        locals: { messages: { error: [], success: [], info: [] } },
        body: undefined,
        view: null,
        redirectedTo: null,
        finished: false,
        done,
        status(code) {
            this.statusCode = code;
            return this;
        },
        set(name, value) {
            this.headers[name.toLowerCase()] = value;
            return this;
        },
        json(value) {
            this.body = value;
            complete(this);
            return this;
        },
        send(value) {
            this.body = value;
            complete(this);
            return this;
        },
        render(view, locals) {
            this.view = view;
            this.body = locals;
            complete(this);
            return this;
        },
        redirect(location) {
            this.redirectedTo = location;
            complete(this);
            return this;
        }
    };

    function complete(target) {
        if (target.finished) return;
        target.finished = true;
        finish(target);
    }

    return response;
}

function createRequest(overrides = {}) {
    const flashes = [];
    return {
        body: {},
        params: {},
        query: {},
        headers: {},
        socket: { remoteAddress: '127.0.0.1' },
        session: { user: { id: 1, username: 'tester', type: 'local' } },
        flashes,
        flash(type, message) {
            flashes.push({ type, message });
            return 1;
        },
        get() {
            return undefined;
        },
        ...overrides
    };
}

function patchObject(target, replacements) {
    const originals = new Map();
    for (const [key, value] of Object.entries(replacements)) {
        originals.set(key, target[key]);
        target[key] = value;
    }

    return () => {
        for (const [key, value] of originals) {
            target[key] = value;
        }
    };
}

function installModuleMock(modulePath, exportsValue) {
    const resolvedPath = require.resolve(modulePath);
    const previous = require.cache[resolvedPath];
    require.cache[resolvedPath] = {
        id: resolvedPath,
        filename: resolvedPath,
        loaded: true,
        exports: exportsValue,
        children: [],
        paths: module.paths
    };

    return () => {
        delete require.cache[resolvedPath];
        if (previous) require.cache[resolvedPath] = previous;
    };
}

function freshRequire(modulePath) {
    const resolvedPath = require.resolve(modulePath);
    delete require.cache[resolvedPath];
    return require(resolvedPath);
}

function projectPath(...segments) {
    return path.join(__dirname, '..', ...segments);
}

module.exports = {
    createRequest,
    createResponse,
    freshRequire,
    getRouteHandler,
    installModuleMock,
    patchObject,
    projectPath
};
