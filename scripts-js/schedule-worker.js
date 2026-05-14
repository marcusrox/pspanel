/**
 * Worker de agendamentos — executar a partir da raiz do projeto:
 *   node scripts-js/schedule-worker.js
 * Ou via scripts-ps/Invoke-ScheduleWorker.ps1 (Task Scheduler a cada 5 min).
 */
const path = require('path');

const projectRoot = path.join(__dirname, '..');
process.chdir(projectRoot);

const Schedule = require(path.join(projectRoot, 'src', 'models', 'Schedule'));

async function main() {
    await Schedule.initialize();
    const results = await Schedule.executeDueJobs(projectRoot);
    if (results.length) {
        console.log(JSON.stringify({ ran: results.length, results }, null, 2));
    } else {
        console.log('Nenhum agendamento vencido.');
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
