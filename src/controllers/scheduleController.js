const path = require('path');
const fs = require('fs').promises;
const fsSync = require('fs');
const Schedule = require('../models/Schedule');
const {
    SCHEDULE_TIMEZONE,
    SCHEDULE_TYPES,
    CADENCES,
    ALLOWED_MINUTE_INTERVALS,
    ALLOWED_HOUR_INTERVALS,
    buildCronExpression,
    parseCronExpression,
    getNextOccurrence,
    describeCronExpression,
    zonedDateTimeToIso,
    isoToDatetimeLocal
} = require('../services/scheduleRecurrence');
const {
    parseScriptParametersFromContent,
    getMissingRequiredParameters,
    parseRawNamedParameters,
    getUnknownPowerShellArgs,
    formatCommandLineArg,
    formatProvidedParams,
    redactSensitiveParameters,
    redactSensitiveText
} = require('../services/powerShellParameters');
const { getRequestAuditContext } = require('../services/requestAuditContext');

function buildAuditContext(req) {
    const requestContext = getRequestAuditContext(req);
    return {
        userId: req.session.user.id,
        username: req.session.user.username,
        authType: req.session.user.type,
        clientIp: requestContext.clientIp
    };
}

async function listScriptsWithParameters(projectRoot) {
    const scriptsDir = path.join(projectRoot, 'scripts-ps');
    const files = await fs.readdir(scriptsDir);
    const scripts = [];

    for (const file of files.filter((f) => f.endsWith('.ps1')).sort()) {
        const scriptPath = path.join(scriptsDir, file);
        try {
            const content = await fs.readFile(scriptPath, 'utf8');
            scripts.push({
                name: file,
                parameters: parseScriptParametersFromContent(content)
            });
        } catch (error) {
            console.error(`Erro ao ler parametros do script ${scriptPath}:`, error);
            scripts.push({ name: file, parameters: null });
        }
    }

    return scripts;
}

function isValidScriptName(name) {
    return typeof name === 'string' && name.endsWith('.ps1') && !name.includes('..') && !name.includes('/') && !name.includes('\\');
}

async function getScriptParameterDefinitions(scriptPath) {
    const source = await fs.readFile(scriptPath, 'utf8');
    const parameterInfo = parseScriptParametersFromContent(source);
    return parameterInfo && Array.isArray(parameterInfo.parameters)
        ? parameterInfo.parameters
        : [];
}

function normalizeProvidedParamValues(paramValues) {
    return paramValues && typeof paramValues === 'object' ? paramValues : {};
}

function buildScheduleFormValues(schedule, parameterDefinitions) {
    if (!schedule || !schedule.parameters) {
        return { parameterValues: {}, additionalParameters: '' };
    }

    return {
        parameterValues: parseRawNamedParameters(schedule.parameters, parameterDefinitions),
        additionalParameters: getUnknownPowerShellArgs(schedule.parameters, parameterDefinitions)
            .map(formatCommandLineArg)
            .join(' ')
    };
}

function buildScheduleListItem(schedule) {
    const {
        parameters,
        last_run_output: lastRunOutput,
        ...safeSchedule
    } = schedule;
    const redactedParameters = redactSensitiveParameters(parameters);

    return {
        ...safeSchedule,
        parameters: redactedParameters.maskedParameters,
        last_run_output: redactSensitiveText(lastRunOutput, redactedParameters.sensitiveValues),
        recurrence_description: schedule.schedule_type === SCHEDULE_TYPES.CRON
            ? describeCronExpression(schedule.cron_expression)
            : 'Uma vez'
    };
}

function getDefaultRecurrenceForm() {
    return {
        days: ['0', '1', '2', '3', '4', '5', '6'],
        cadence: CADENCES.FIXED_TIME,
        time: '08:00',
        interval: '1'
    };
}

function buildRecurrenceForm(schedule) {
    if (!schedule || schedule.schedule_type !== SCHEDULE_TYPES.CRON) {
        return getDefaultRecurrenceForm();
    }

    const parsed = parseCronExpression(schedule.cron_expression);
    return {
        days: parsed.days.map(String),
        cadence: parsed.cadence,
        time: parsed.time || '08:00',
        interval: String(parsed.interval || 1)
    };
}

function buildTimingValues(body) {
    if (body.schedule_type === SCHEDULE_TYPES.ONCE) {
        return {
            schedule_type: SCHEDULE_TYPES.ONCE,
            cron_expression: null,
            schedule_timezone: SCHEDULE_TIMEZONE,
            next_run_at: zonedDateTimeToIso(body.next_run_at, SCHEDULE_TIMEZONE)
        };
    }

    if (body.schedule_type !== SCHEDULE_TYPES.CRON) {
        throw new Error('Selecione um tipo de agendamento válido.');
    }

    const cronExpression = buildCronExpression({
        days: body.recurrence_days,
        cadence: body.recurrence_cadence,
        time: body.recurrence_time,
        interval: body.recurrence_interval
    });
    return {
        schedule_type: SCHEDULE_TYPES.CRON,
        cron_expression: cronExpression,
        schedule_timezone: SCHEDULE_TIMEZONE,
        next_run_at: getNextOccurrence(cronExpression, { timezone: SCHEDULE_TIMEZONE })
    };
}

exports.list = async (req, res) => {
    try {
        const schedules = (await Schedule.findAll()).map(buildScheduleListItem);
        res.render('schedules', {
            user: req.session.user,
            schedules,
            messages: res.locals.messages
        });
    } catch (e) {
        console.error(e);
        req.flash('error', 'Erro ao carregar agendamentos.');
        res.render('schedules', { user: req.session.user, schedules: [], messages: res.locals.messages });
    }
};

exports.audit = async (req, res) => {
    const scriptNameFilter = typeof req.query.script_name === 'string'
        ? req.query.script_name.trim().slice(0, 255)
        : '';

    try {
        const entries = await Schedule.listAudit(300, { script_name: scriptNameFilter });
        res.render('schedule-audit', {
            user: req.session.user,
            entries,
            filters: { script_name: scriptNameFilter },
            messages: res.locals.messages
        });
    } catch (e) {
        console.error(e);
        req.flash('error', 'Erro ao carregar auditoria.');
        res.render('schedule-audit', {
            user: req.session.user,
            entries: [],
            filters: { script_name: scriptNameFilter },
            messages: res.locals.messages
        });
    }
};

exports.newForm = async (req, res) => {
    try {
        const scripts = await listScriptsWithParameters(process.cwd());
        if (!scripts.length) {
            req.flash('error', 'Não há scripts .ps1 em scripts-ps. Adicione um script antes de agendar.');
            return res.redirect('/schedules');
        }
        res.render('schedule-form', {
            user: req.session.user,
            mode: 'new',
            schedule: null,
            scripts,
            parameterValues: {},
            additionalParameters: '',
            next_run_local: isoToDatetimeLocal(new Date(Date.now() + 5 * 60 * 1000).toISOString()),
            recurrenceForm: getDefaultRecurrenceForm(),
            recurrenceOptions: {
                timezone: SCHEDULE_TIMEZONE,
                types: SCHEDULE_TYPES,
                cadences: CADENCES,
                minuteIntervals: ALLOWED_MINUTE_INTERVALS,
                hourIntervals: ALLOWED_HOUR_INTERVALS
            },
            messages: res.locals.messages
        });
    } catch (e) {
        console.error(e);
        req.flash('error', 'Erro ao carregar formulário.');
        res.redirect('/schedules');
    }
};

exports.editForm = async (req, res) => {
    try {
        const id = parseInt(req.params.id, 10);
        const schedule = await Schedule.findById(id);
        if (!schedule) {
            req.flash('error', 'Agendamento não encontrado.');
            return res.redirect('/schedules');
        }
        const scripts = await listScriptsWithParameters(process.cwd());
        const scriptNames = scripts.map((script) => script.name);
        if (schedule.script_name && !scriptNames.includes(schedule.script_name)) {
            scripts.push({ name: schedule.script_name, parameters: null });
            scripts.sort((a, b) => a.name.localeCompare(b.name));
        }
        const selectedScript = scripts.find((script) => script.name === schedule.script_name);
        const parameterDefinitions = selectedScript && selectedScript.parameters && Array.isArray(selectedScript.parameters.parameters)
            ? selectedScript.parameters.parameters
            : [];
        const formValues = buildScheduleFormValues(schedule, parameterDefinitions);
        res.render('schedule-form', {
            user: req.session.user,
            mode: 'edit',
            schedule,
            scripts,
            parameterValues: formValues.parameterValues,
            additionalParameters: formValues.additionalParameters,
            next_run_local: schedule.schedule_type === SCHEDULE_TYPES.ONCE
                ? isoToDatetimeLocal(schedule.next_run_at, schedule.schedule_timezone)
                : '',
            recurrenceForm: buildRecurrenceForm(schedule),
            recurrenceOptions: {
                timezone: SCHEDULE_TIMEZONE,
                types: SCHEDULE_TYPES,
                cadences: CADENCES,
                minuteIntervals: ALLOWED_MINUTE_INTERVALS,
                hourIntervals: ALLOWED_HOUR_INTERVALS
            },
            messages: res.locals.messages
        });
    } catch (e) {
        console.error(e);
        req.flash('error', 'Erro ao carregar agendamento.');
        res.redirect('/schedules');
    }
};

exports.create = async (req, res) => {
    const { script_name, parameters, paramValues, enabled } = req.body;
    const scriptPath = path.join(process.cwd(), 'scripts-ps', script_name || '');

    if (!isValidScriptName(script_name) || !fsSync.existsSync(scriptPath)) {
        req.flash('error', 'Selecione um script .ps1 válido da pasta scripts-ps.');
        return res.redirect('/schedules/new');
    }

    let timing;
    try {
        timing = buildTimingValues(req.body);
    } catch (error) {
        req.flash('error', error.message);
        return res.redirect('/schedules/new');
    }

    try {
        const parameterDefinitions = await getScriptParameterDefinitions(scriptPath);
        const rawParamValues = parseRawNamedParameters(parameters, parameterDefinitions);
        const providedParamValues = {
            ...rawParamValues,
            ...normalizeProvidedParamValues(paramValues)
        };
        const missingRequiredParameters = getMissingRequiredParameters(parameterDefinitions, providedParamValues);
        if (missingRequiredParameters.length) {
            req.flash('error', `Informe os parâmetros obrigatórios: ${missingRequiredParameters.join(', ')}.`);
            return res.redirect('/schedules/new');
        }

        await Schedule.create({
            script_name,
            parameters: formatProvidedParams(parameterDefinitions, paramValues, parameters),
            enabled: !!enabled,
            ...timing,
            created_by: req.session.user.username,
            audit_context: buildAuditContext(req)
        });
        req.flash('success', 'Agendamento criado.');
        res.redirect('/schedules');
    } catch (e) {
        console.error(e);
        req.flash('error', 'Erro ao criar agendamento.');
        res.redirect('/schedules/new');
    }
};

exports.update = async (req, res) => {
    const id = parseInt(req.params.id, 10);
    const { script_name, parameters, paramValues, enabled } = req.body;
    const scriptPath = path.join(process.cwd(), 'scripts-ps', script_name || '');

    if (!isValidScriptName(script_name) || !fsSync.existsSync(scriptPath)) {
        req.flash('error', 'Selecione um script .ps1 válido.');
        return res.redirect(`/schedules/${id}/edit`);
    }

    let timing;
    try {
        timing = buildTimingValues(req.body);
    } catch (error) {
        req.flash('error', error.message);
        return res.redirect(`/schedules/${id}/edit`);
    }

    try {
        const existing = await Schedule.findById(id);
        if (!existing) {
            req.flash('error', 'Agendamento não encontrado.');
            return res.redirect('/schedules');
        }
        const parameterDefinitions = await getScriptParameterDefinitions(scriptPath);
        const rawParamValues = parseRawNamedParameters(parameters, parameterDefinitions);
        const providedParamValues = {
            ...rawParamValues,
            ...normalizeProvidedParamValues(paramValues)
        };
        const missingRequiredParameters = getMissingRequiredParameters(parameterDefinitions, providedParamValues);
        if (missingRequiredParameters.length) {
            req.flash('error', `Informe os parâmetros obrigatórios: ${missingRequiredParameters.join(', ')}.`);
            return res.redirect(`/schedules/${id}/edit`);
        }

        await Schedule.update(
            id,
            {
                script_name,
                parameters: formatProvidedParams(parameterDefinitions, paramValues, parameters),
                enabled: !!enabled,
                ...timing
            },
            buildAuditContext(req)
        );
        req.flash('success', 'Agendamento atualizado.');
        res.redirect('/schedules');
    } catch (e) {
        console.error(e);
        req.flash('error', 'Erro ao atualizar agendamento.');
        res.redirect(`/schedules/${id}/edit`);
    }
};

exports.delete = async (req, res) => {
    const id = parseInt(req.params.id, 10);
    try {
        const existing = await Schedule.findById(id);
        if (!existing) {
            req.flash('error', 'Agendamento não encontrado.');
            return res.redirect('/schedules');
        }
        await Schedule.delete(id, buildAuditContext(req));
        req.flash('success', 'Agendamento excluído.');
    } catch (e) {
        console.error(e);
        req.flash('error', 'Erro ao excluir agendamento.');
    }
    res.redirect('/schedules');
};
