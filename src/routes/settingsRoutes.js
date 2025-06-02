const express = require('express');
const router = express.Router();
const SettingsController = require('../controllers/settingsController');

// Rotas de configurações
router.get('/', SettingsController.showSettings);
router.post('/update', SettingsController.updateSettings);

module.exports = router; 