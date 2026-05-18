(function () {
    let renameScriptState = {
        currentName: '',
        renameUrl: '',
        triggerButton: null,
        isLoading: false
    };

    function renameScript(event, button) {
        event.preventDefault();
        event.stopPropagation();

        const currentName = button.getAttribute('data-script-name');
        const renameUrl = button.getAttribute('data-rename-url');
        openRenameScriptModal(currentName, renameUrl, button);
    }

    function openRenameScriptModal(currentName, renameUrl, triggerButton) {
        const modal = document.getElementById('renameScriptModal');
        const input = document.getElementById('renameScriptInput');
        const currentNameLabel = document.getElementById('renameCurrentName');

        renameScriptState = {
            currentName,
            renameUrl,
            triggerButton,
            isLoading: false
        };

        currentNameLabel.textContent = currentName;
        input.value = currentName;
        setRenameScriptLoading(false);
        showRenameScriptError('');

        modal.classList.add('is-open');
        modal.setAttribute('aria-hidden', 'false');
        setTimeout(function () {
            input.focus();
            input.select();
        }, 0);
    }

    function closeRenameScriptModal() {
        const modal = document.getElementById('renameScriptModal');

        if (!modal.classList.contains('is-open')) {
            return;
        }

        if (renameScriptState.isLoading) {
            return;
        }

        modal.classList.remove('is-open');
        modal.setAttribute('aria-hidden', 'true');
        showRenameScriptError('');
        setRenameScriptLoading(false);

        if (renameScriptState.triggerButton) {
            renameScriptState.triggerButton.focus();
        }
    }

    function handleRenameModalBackdrop(event) {
        if (event.target.id === 'renameScriptModal') {
            closeRenameScriptModal();
        }
    }

    async function submitRenameScript(event) {
        event.preventDefault();

        const input = document.getElementById('renameScriptInput');
        const newScriptName = input.value.trim();

        if (!newScriptName) {
            showRenameScriptError('Informe o novo nome do script.');
            input.focus();
            return;
        }

        if (newScriptName === renameScriptState.currentName) {
            showRenameScriptError('Informe um nome diferente do atual.');
            input.focus();
            return;
        }

        const validationError = getRenameScriptValidationError(newScriptName);
        if (validationError) {
            showRenameScriptError(validationError);
            input.focus();
            return;
        }

        setRenameScriptLoading(true);
        showRenameScriptError('');

        try {
            const response = await fetch(renameScriptState.renameUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ newScriptName })
            });

            const data = await response.json().catch(() => null);

            if (!response.ok) {
                showRenameScriptError(data && data.error ? data.error : 'Nao foi possivel renomear o script.');
                return;
            }

            window.location.reload();
        } catch (error) {
            console.error('Erro ao renomear script:', error);
            showRenameScriptError('Nao foi possivel renomear o script.');
        } finally {
            setRenameScriptLoading(false);
        }
    }

    function showRenameScriptError(message) {
        const errorBox = document.getElementById('renameScriptError');
        errorBox.textContent = message;
        errorBox.classList.toggle('is-visible', Boolean(message));
    }

    function getRenameScriptValidationError(scriptName) {
        if (scriptName.includes('..') || scriptName.includes('/') || scriptName.includes('\\')) {
            return 'Informe apenas o nome do arquivo, sem caminho ou subpastas.';
        }

        const hasExtension = scriptName.includes('.');
        if (hasExtension && !scriptName.toLowerCase().endsWith('.ps1')) {
            return 'Use um nome sem extensao ou com a extensao .ps1.';
        }

        return '';
    }

    function setRenameScriptLoading(isLoading) {
        const submitBtn = document.getElementById('renameSubmitBtn');
        renameScriptState.isLoading = isLoading;
        submitBtn.disabled = isLoading;
        submitBtn.innerHTML = isLoading
            ? '<i class="fas fa-spinner fa-spin"></i> Salvando...'
            : '<i class="fas fa-save"></i> Salvar';

        if (renameScriptState.triggerButton) {
            renameScriptState.triggerButton.disabled = isLoading;
        }
    }

    document.addEventListener('keydown', function (event) {
        if (event.key === 'Escape') {
            closeRenameScriptModal();
        }
    });

    window.renameScript = renameScript;
    window.closeRenameScriptModal = closeRenameScriptModal;
    window.handleRenameModalBackdrop = handleRenameModalBackdrop;
    window.submitRenameScript = submitRenameScript;
})();
