/**
 * Worker de agendamentos — executar a partir da raiz do projeto:
 *   node scripts-js/schedule-worker.js
 * Ou via scripts-ps/Invoke-ScheduleWorker.ps1 (Task Scheduler a cada 5 min).
 */
const path = require('path');

const projectRoot = path.join(__dirname, '..');
process.chdir(projectRoot);

const Schedule = require(path.join(projectRoot, 'src', 'models', 'Schedule'));
const History = require(path.join(projectRoot, 'src', 'models', 'History'));
const Settings = require(path.join(projectRoot, 'src', 'models', 'Settings'));
const { sendPendingDailySummary } = require(path.join(projectRoot, 'src', 'services', 'dailySummaryEmailService'));

async function main() {
    await Schedule.initialize();
    await Settings.initialize();
    await History.initialize();

    const results = await Schedule.executeDueJobs(projectRoot);
    if (results.length) {
        console.log(JSON.stringify({ ran: results.length, results }, null, 2));
    } else {
        console.log('Nenhum agendamento vencido.');
    }

    try {
        const summaryResult = await sendPendingDailySummary();
        if (summaryResult.sent) {
            console.log(`Resumo diario de ${summaryResult.reportDate} enviado para ${summaryResult.recipient}.`);
        } else if (summaryResult.reason === 'disabled') {
            console.log('Resumo diario de agendamentos desabilitado.');
        } else if (summaryResult.reason === 'already_sent') {
            console.log(`Resumo diario de ${summaryResult.reportDate} ja enviado.`);
        } else if (summaryResult.reason === 'missing_config') {
            console.log(`Resumo diario nao enviado: configuracao incompleta (${summaryResult.missingConfig.join(', ')}).`);
        }
    } catch (error) {
        console.error('Falha ao enviar resumo diario de agendamentos:', error.message || error);
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
