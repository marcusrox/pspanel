const express = require('express');
const router = express.Router();
const scheduleController = require('../controllers/scheduleController');

router.get('/audit', scheduleController.audit);
router.get('/new', scheduleController.newForm);
router.post('/', scheduleController.create);
router.get('/:id/edit', scheduleController.editForm);
router.post('/:id', scheduleController.update);
router.post('/:id/delete', scheduleController.delete);
router.get('/', scheduleController.list);

module.exports = router;
