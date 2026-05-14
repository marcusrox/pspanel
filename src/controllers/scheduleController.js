const path = require('path');
const fs = require('fs').promises;
const fsSync = require('fs');
const Schedule = require('../models/Schedule');

async function listScriptNames(projectRoot) {
    const scriptsDir = path.join(projectRoot, 'scripts-ps');
    const files = await fs.readdir(scriptsDir);
    return files.filter((f) => f.endsWith('.ps1')).sort();
}

function isValidScriptName(name) {
    return typeof name === 'string' && name.endsWith('.ps1') && !name.includes('..') && !name.includes('/') && !name.includes('\\');
}

function toDatetimeLocalValue(isoString) {
    if (!isoString) return '';
    const d = new Date(isoString);
    if (Number.isNaN(d.getTime())) return '';
    const pad = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

exports.list = async (req, res) => {
    try {
        const schedules = await Schedule.findAll();
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
    try {
        const entries = await Schedule.listAudit(300);
        res.render('schedule-audit', {
            user: req.session.user,
            entries,
            messages: res.locals.messages
        });
    } catch (e) {
        console.error(e);
        req.flash('error', 'Erro ao carregar auditoria.');
        res.render('schedule-audit', { user: req.session.user, entries: [], messages: res.locals.messages });
    }
};

exports.newForm = async (req, res) => {
    try {
        const scripts = await listScriptNames(process.cwd());
        if (!scripts.length) {
            req.flash('error', 'Não há scripts .ps1 em scripts-ps. Adicione um script antes de agendar.');
            return res.redirect('/schedules');
        }
        res.render('schedule-form', {
            user: req.session.user,
            mode: 'new',
            schedule: null,
            scripts,
            next_run_local: toDatetimeLocalValue(new Date(Date.now() + 5 * 60 * 1000).toISOString()),
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
        const scripts = await listScriptNames(process.cwd());
        if (schedule.script_name && !scripts.includes(schedule.script_name)) {
            scripts.push(schedule.script_name);
            scripts.sort();
        }
        res.render('schedule-form', {
            user: req.session.user,
            mode: 'edit',
            schedule,
            scripts,
            next_run_local: toDatetimeLocalValue(schedule.next_run_at),
            messages: res.locals.messages
        });
    } catch (e) {
        console.error(e);
        req.flash('error', 'Erro ao carregar agendamento.');
        res.redirect('/schedules');
    }
};

exports.create = async (req, res) => {
    const { script_name, parameters, enabled, next_run_at, repeat_interval_minutes } = req.body;
    const scriptPath = path.join(process.cwd(), 'scripts-ps', script_name || '');

    if (!isValidScriptName(script_name) || !fsSync.existsSync(scriptPath)) {
        req.flash('error', 'Selecione um script .ps1 válido da pasta scripts-ps.');
        return res.redirect('/schedules/new');
    }

    const nextIso = next_run_at ? new Date(next_run_at).toISOString() : null;
    if (!nextIso || Number.isNaN(new Date(nextIso).getTime())) {
        req.flash('error', 'Data/hora de execução inválida.');
        return res.redirect('/schedules/new');
    }

    try {
        await Schedule.create({
            script_name,
            parameters: parameters || '',
            enabled: !!enabled,
            next_run_at: nextIso,
            repeat_interval_minutes: repeat_interval_minutes || null,
            created_by: req.session.user.username
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
    const { script_name, parameters, enabled, next_run_at, repeat_interval_minutes } = req.body;
    const scriptPath = path.join(process.cwd(), 'scripts-ps', script_name || '');

    if (!isValidScriptName(script_name) || !fsSync.existsSync(scriptPath)) {
        req.flash('error', 'Selecione um script .ps1 válido.');
        return res.redirect(`/schedules/${id}/edit`);
    }

    const nextIso = next_run_at ? new Date(next_run_at).toISOString() : null;
    if (!nextIso || Number.isNaN(new Date(nextIso).getTime())) {
        req.flash('error', 'Data/hora de execução inválida.');
        return res.redirect(`/schedules/${id}/edit`);
    }

    try {
        const existing = await Schedule.findById(id);
        if (!existing) {
            req.flash('error', 'Agendamento não encontrado.');
            return res.redirect('/schedules');
        }
        await Schedule.update(
            id,
            {
                script_name,
                parameters: parameters || '',
                enabled: !!enabled,
                next_run_at: nextIso,
                repeat_interval_minutes: repeat_interval_minutes || null
            },
            req.session.user.username
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
        await Schedule.delete(id, req.session.user.username);
        req.flash('success', 'Agendamento excluído.');
    } catch (e) {
        console.error(e);
        req.flash('error', 'Erro ao excluir agendamento.');
    }
    res.redirect('/schedules');
};
