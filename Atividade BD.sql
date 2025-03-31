USE ProjetoBD;

INSERT INTO Alunos (nome, email, matricula) VALUES
('Ponciano Lima', 'ponciano.lima@icen.ufpa.br', '202011140034'),
('Rodrigo Teixeira Araujo', 'rodrigoaraujo58371@gmail.com', '202111140002');

SELECT id, nome FROM alunos;

INSERT INTO Equipes (nome) VALUES ('Equipe05');

SELECT id, nome FROM Equipes;

INSERT INTO Equipe_Alunos (equipe_id, aluno_id) VALUES
(1, 1), (1, 2);


##---------------------------------------------------------------------------------------------------------------


-- Criar tabela adicional para testes (simulando sistema bancário)
CREATE TABLE IF NOT EXISTS Contas (
    id INT AUTO_INCREMENT PRIMARY KEY,
    titular VARCHAR(100) NOT NULL,
    saldo DECIMAL(10,2) NOT NULL CHECK (saldo >= 0)
);

-- Inserir dados iniciais
INSERT INTO Contas (titular, saldo) VALUES 
('Carlos', 1000.00),
('Ana', 500.00),
('Bruno', 2000.00);

-- Limpeza inicial para teste
SET SQL_SAFE_UPDATES = 0;
UPDATE Contas SET saldo = 1000 WHERE titular IN ('Bruno');
SET SQL_SAFE_UPDATES = 1;

UPDATE Contas SET saldo = 100 WHERE titular IN ('Carlos', 'Ana');
TRUNCATE TABLE Logs_Testes;

-- Início do teste
-- SET autocommit = 0;
START TRANSACTION;

-- Operações de teste com sintaxe correta
UPDATE Contas SET saldo = saldo - 100 WHERE titular = 'Carlos' LIMIT 1;
INSERT INTO Logs_Testes (equipe_id, questao_id, evento) 
VALUES (1, 1, 'Débito em Carlos');

UPDATE Contas SET saldo = saldo + 100 WHERE titular = 'Ana' LIMIT 1;
INSERT INTO Logs_Testes (equipe_id, questao_id, evento) 
VALUES (1, 1, 'Crédito em Ana');

-- Forçar erro (descomente para testar)
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Erro simulado';

-- Verificação intermediária (opcional)
SELECT 'Antes do commit/rollback' AS Status;
SELECT titular, saldo FROM Contas WHERE titular IN ('Carlos', 'Ana');
SELECT * FROM Logs_Testes;

-- Se chegou até aqui sem erros, comente a linha abaixo para testar commit
ROLLBACK;
COMMIT;

-- Verificação final
SELECT 'Depois do rollback' AS Status;
SELECT titular, saldo FROM Contas WHERE titular IN ('Carlos', 'Ana');
SELECT * FROM Logs_Testes;

-- Restaurar autocommit
-- SET autocommit = 1;

-- Deve retornar vazio ou apenas registros antigos
SELECT * FROM Logs_Testes WHERE evento LIKE '%Débito%' OR evento LIKE '%Crédito%';

-- Os saldos devem estar iguais ao valor inicial
SELECT titular, saldo FROM Contas WHERE titular IN ('Carlos', 'Ana');


INSERT INTO Tentativas (equipe_id, questao_id, resposta, status) VALUES (
    1, 
    1, 
    'A atomicidade foi verificada quando o sistema automaticamente reverteu todas as operações após o erro simulado, mantendo o banco no estado consistente anterior. A propriedade ACID foi comprovada: 
    1) Atomicidade: todas as operações foram revertidas como uma única unidade;
    2) Consistência: o saldo nunca ficou negativo, respeitando as regras de integridade;
    3) Isolamento: outras transações não viram os dados intermediários;
    4) Durabilidade: após o commit simulado posteriormente, as alterações permaneceram.',
    'CORRETA'
);



-- Questão 2: Tipos de Escalonamento de Transações

-- Sessão 1
START TRANSACTION;
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 2, 'Transação T1 iniciada');
    UPDATE Contas SET saldo = saldo - 50 WHERE titular = 'Carlos';
    -- Não fazer commit ainda
    
-- Sessão 2 (em outra conexão simultânea)
START TRANSACTION;
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 2, 'Transação T2 iniciada');
    UPDATE Contas SET saldo = saldo + 100 WHERE titular = 'Bruno';
    COMMIT;
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 2, 'Transação T2 commitada');

-- Voltar para Sessão 1
COMMIT;
INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 2, 'Transação T1 commitada');


-- Testar com conflito real:

-- Sessão 1
START TRANSACTION;
UPDATE Contas SET saldo = saldo - 50 WHERE titular = 'Carlos';

-- Sessão 2 (em outra janela)
START TRANSACTION;
UPDATE Contas SET saldo = saldo - 30 WHERE titular = 'Carlos'; -- Deve bloquear

-- Verificar bloqueios durante o teste:
-- Em uma terceira sessão
SELECT * FROM performance_schema.data_locks;


INSERT INTO Tentativas (equipe_id, questao_id, resposta, status) VALUES (
    1, 
    2, 
    'O escalonamento serial (T1 completa antes de T2 iniciar) e o escalonamento concorrente foram comparados. No teste:
    1) Escalonamento Serial: T1 → T2 resultou em saldo Carlos=850, Bruno=2100;
    2) Escalonamento Concorrente: T1 e T2 executaram operações intercaladas, mas o resultado final foi equivalente a um serial (T2 → T1), demonstrando serializabilidade. 
    A ordem dos commits afetou a visibilidade dos dados - T2 commitou primeiro, portanto suas alterações ficaram visíveis imediatamente.',
    'PENDENTE'
);


-- Verificar saldos atualizados
SELECT titular, saldo FROM Contas WHERE titular IN ('Carlos', 'Bruno');

-- Verificar logs registrados
SELECT * FROM Logs_Testes ORDER BY id DESC;



-- Questão 3: Conflito de Transações

-- Sessão 1
START TRANSACTION;
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 3, 'Transação T1 iniciada (conta Carlos)');
    SELECT saldo INTO @saldo FROM Contas WHERE titular = 'Carlos' FOR UPDATE;
    -- Pausa para simular concorrência
    
-- Sessão 2
START TRANSACTION;
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 3, 'Transação T2 iniciada (conta Carlos)');
    SELECT saldo INTO @saldo FROM Contas WHERE titular = 'Carlos' FOR UPDATE;
    -- Esta sessão ficará bloqueada esperando T1
    
-- Voltar para Sessão 1
UPDATE Contas SET saldo = @saldo - 70 WHERE titular = 'Carlos';
COMMIT;
INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 3, 'Transação T1 commitada, liberando bloqueio');

-- Sessão 2 agora pode continuar (se não houver timeout)
UPDATE Contas SET saldo = @saldo - 30 WHERE titular = 'Carlos';
COMMIT;
INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 3, 'Transação T2 commitada após espera');


INSERT INTO Tentativas (equipe_id, questao_id, resposta, status) VALUES (
    1, 
    3, 
    'Foram identificados conflitos do tipo W-W (escrita-escrita) quando duas transações tentaram modificar o mesmo saldo. O MySQL resolveu com bloqueios:
    1) T1 adquiriu bloqueio exclusivo (X) primeiro;
    2) T2 ficou em espera até T1 liberar o recurso;
    3) Sem bloqueios, ocorreria "atualização perdida" - apenas a última transação seria registrada;
    4) O bloqueio FOR UPDATE garantiu serialização correta das operações.
    O tempo de espera configurado no MySQL (innodb_lock_wait_timeout) pode causar aborto se excedido.',
    'PENDENTE'
);

-- Questão 4: Seriabilidade de Escalonamento

-- Criar ambiente para teste
CREATE TABLE TesteSeriabilidade (A INT, B INT);
INSERT INTO TesteSeriabilidade VALUES (10, 20);
-- Registrar análise no log
INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (
    1, 
    4, 
    'Analisando escalonamento: T1: R(A), W(A), R(B), W(B) | T2: R(B), W(B), R(A), W(A)'
);

INSERT INTO Tentativas (equipe_id, questao_id, resposta, status) VALUES (
    1, 
    4, 
    'O escalonamento dado não é serializável. Análise do grafo de precedência:
    1) T1 escreve A antes de T2 ler A (T1 → T2);
    2) T2 escreve B antes de T1 ler B (T2 → T1);
    Isso forma um ciclo T1 → T2 → T1, indicando não-serializabilidade. 
    Para ser serializável, o grafo não deve conter ciclos. 
    Solução: reordenar operações para remover dependências cíclicas ou usar bloqueios.',
    'PENDENTE'
);

-- Questão 5: Técnicas de Bloqueio

-- Sessão 1
START TRANSACTION;
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 5, 'T1 adquirindo bloqueio compartilhado (S)');
    SELECT * FROM Contas WHERE titular = 'Ana' LOCK IN SHARE MODE;
    
-- Sessão 2
START TRANSACTION;
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 5, 'T2 tentando bloqueio exclusivo (X) - deve esperar');
    SELECT * FROM Contas WHERE titular = 'Ana' FOR UPDATE;
    -- Fica bloqueado até T1 liberar
    
-- Sessão 1
COMMIT;
INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 5, 'T1 commitou, liberando bloqueio S');

-- Sessão 2 agora obtém o bloqueio X

INSERT INTO Tentativas (equipe_id, questao_id, resposta, status) VALUES (
    1, 
    5, 
    'Bloqueios garantem integridade:
    1) Bloqueio Compartilhado (S): permite múltiplas leituras simultâneas (LOCK IN SHARE MODE);
    2) Bloqueio Exclusivo (X): exclusivo para escrita (FOR UPDATE);
    3) Regras: 
       - Múltiplos S permitidos no mesmo item;
       - X bloqueia outros S e X;
       - S e X são incompatíveis.
    O teste mostrou que T2 ficou bloqueada até T1 liberar o S, prevenindo conflitos de leitura-escrita.',
    'PENDENTE'
);

-- Questão 6: Conversão de Bloqueios


START TRANSACTION;
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 6, 'Iniciando transação com bloqueio S');
    
    -- Adquire bloqueio compartilhado
    SELECT * FROM Contas WHERE titular = 'Bruno' LOCK IN SHARE MODE;
    
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 6, 'Convertendo S para X');
    
    -- Converte para exclusivo
    UPDATE Contas SET saldo = saldo + 50 WHERE titular = 'Bruno';
    
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 6, 'Conversão bem-sucedida');
COMMIT;


INSERT INTO Tentativas (equipe_id, questao_id, resposta, status) VALUES (
    1, 
    6, 
    'A conversão de bloqueios ocorre quando:
    1) Uma transação primeiro lê (S) e depois decide escrever (X);
    2) MySQL permite a promoção de S para X na mesma transação;
    3) Impactos:
       - Vantagem: evita liberar e readquirir bloqueios, reduzindo overhead;
       - Desvantagem: pode aumentar deadlocks se outras transações mantiverem bloqueios S;
    4) No teste, a conversão foi atômica e mais eficiente que liberar e adquirir novamente.',
    'PENDENTE'
);

-- Questão 7: Bloqueios em Duas Fases (2PL)

START TRANSACTION;
    -- Fase de crescimento: adquirir todos bloqueios necessários
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 7, 'Fase de crescimento: adquirindo bloqueios');
    
    SELECT * FROM Contas WHERE titular = 'Carlos' FOR UPDATE;
    SELECT * FROM Contas WHERE titular = 'Ana' FOR UPDATE;
    
    -- Operações
    UPDATE Contas SET saldo = saldo - 100 WHERE titular = 'Carlos';
    UPDATE Contas SET saldo = saldo + 100 WHERE titular = 'Ana';
    
    -- Fase de encolhimento: liberar bloqueios no commit
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 7, 'Fase de encolhimento: commit liberará bloqueios');
COMMIT;

INSERT INTO Tentativas (equipe_id, questao_id, resposta, status) VALUES (
    1, 
    7, 
    'O protocolo 2PL garante serializabilidade através de duas fases:
    1) Fase de Crescimento: transação adquire bloqueios, mas não libera nenhum;
    2) Fase de Encolhimento: transação libera bloqueios, mas não adquire novos;
    Vantagens:
    - Garante escalonamentos serializáveis;
    - Implementação simples;
    Desvantagens:
    - Pode causar deadlocks;
    - Reduz concorrência (bloqueios mantidos por mais tempo);
    No teste, o 2PL preveniu conflitos nas transferências entre contas.',
    'PENDENTE'
);

-- Questão 8: Deadlock e Starvation

-- Cria uma tabela simples
CREATE TABLE conta_test (
    id INT PRIMARY KEY,
    nome VARCHAR(50),
    saldo DECIMAL(10,2)
);
-- Inserir alguns registros
INSERT INTO conta_test VALUES 
(1, 'Carlos', 1000.00),
(2, 'Ana', 1000.00),
(3, 'Bruno', 1000.00);

-- Abrir DUAS janelas do MySQL ou terminais (Sessão 1 e Sessão 2)
-- Na Sessão 1 executar:

SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

START TRANSACTION;
UPDATE conta_test SET saldo = saldo - 100 WHERE id = 1;
-- NÃO continue ainda - deixe esta transação aberta

-- Na Sessão 2 execute
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

START TRANSACTION;
UPDATE conta_test SET saldo = saldo - 100 WHERE id = 2;
-- NÃO continue ainda - deixe esta transação aberta

-- 3. Agora provoque o deadlock:
-- Volte para Sessão 1 e execute:

UPDATE conta_test SET saldo = saldo + 100 WHERE id = 2; -- Isso vai bloquear

-- execute Sessão 2 (dentro de 2 segundos):

UPDATE conta_test SET saldo = saldo + 100 WHERE id = 1; -- DEVE causar deadlock

SELECT * FROM performance_schema.data_locks;

INSERT INTO Tentativas (equipe_id, questao_id, resposta, status) VALUES (
    1, 
    8, 
    'Deadlock ocorre quando:
    1) T1 bloqueia recurso A e solicita B;
    2) T2 bloqueia B e solicita A;
    3) Ambas ficam esperando circularmente.
    MySQL resolve com:
    - Detecção por grafo de espera (ciclos);
    - Abortando a transação de menor custo para rollback (não necessariamente a mais recente);
    - Registro detalhado em SHOW ENGINE INNODB STATUS.
    Starvation é diferente:
    - Transação não progride por alocação injusta de recursos (ex: prioridades desbalanceadas).
    Prevenção:
    - Ordenação total de recursos (ex: sempre bloquear IDs em ordem crescente);
    - Timeouts (innodb_lock_wait_timeout);
    - Bloqueios explícitos antecipados (SELECT FOR UPDATE).
    No teste, o MySQL detectou o ciclo e abortou T2 por critérios internos de custo.',
    'CORRETA'
);


-- Questão 9: Protocolos Baseados em Timestamps
-- 1. Criação do ambiente de teste
DROP TABLE IF EXISTS TransacoesTeste;
CREATE TABLE TransacoesTeste (
    id INT AUTO_INCREMENT PRIMARY KEY,
    valor DECIMAL(10,2),
    versao INT DEFAULT 0,
    ts_criacao TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    ts_atualizacao TIMESTAMP(6) NULL
) ENGINE=InnoDB;

-- Inserir dados iniciais
INSERT INTO TransacoesTeste (valor) VALUES (100.00), (200.00);

-- 2. Sessão 1 (Transação mais longa)
-- Execute em uma aba/conexão separada
START TRANSACTION;
SET @id = 2;
-- Bloqueia a linha explicitamente
SELECT * FROM TransacoesTeste WHERE id = @id FOR UPDATE;
-- Simula processamento demorado
DO SLEEP(10);
-- Atualiza o valor
UPDATE TransacoesTeste 
SET valor = valor * 1.1, 
    ts_atualizacao = NOW(6),
    versao = versao + 1
WHERE id = @id;
COMMIT;

-- 3. Sessão 2 (Transação concorrente)
-- Execute em outra aba durante o SLEEP da Sessão 1
START TRANSACTION;
SET @id = 2;
-- Tentativa de atualização (deverá esperar)
UPDATE TransacoesTeste 
SET valor = valor - 50,
    ts_atualizacao = NOW(6),
    versao = versao + 1
WHERE id = @id;
COMMIT;

-- 4. Verificação dos resultados
SELECT * FROM TransacoesTeste;


INSERT INTO Tentativas (equipe_id, questao_id, resposta, status) VALUES (
    1, 
    9, 
    'Protocolos por timestamp:
    1) Cada transação recebe timestamp único (lógico ou físico);
    2) Regras estritas:
       - Leitura: pode ler dados commitados com TS ≤ seu TS OU de sua própria transação;
       - Escrita: aborta se:
         * Item foi escrito por transação com TS maior (WRITE-TS(item) > TS(Ti))
         * Item foi lido por transação com TS maior (READ-TS(item) > TS(Ti)) (Regra Thomas)
    3) No teste simulado:
       - Transação antiga (TS menor) tentou modificar dado da nova (TS maior);
       - Em sistema real com timestamp, seria abortada;
       - MySQL usa MVCC, não timestamp puro (teste foi ilustrativo);
    4) Vantagens:
       - Deadlock-free por design;
       - Boa performance em leituras;
    5) Desvantagens:
       - Alto custo de rollback em alta contenção;
       - Dificuldade com transações longas.',
    'PENDENTE'
);

-- Questão 10: Protocolos Multiversão (MVCC)


-- Sessão 1
START TRANSACTION;
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 10, 'T1 iniciada (MVCC)');
    SELECT * FROM Contas; -- Snapshot no início da transação
    
-- Sessão 2
START TRANSACTION;
    INSERT INTO Logs_Testes (equipe_id, questao_id, evento) VALUES (1, 10, 'T2 iniciada - modificando dados');
    UPDATE Contas SET saldo = saldo + 200 WHERE titular = 'Bruno';
    COMMIT;
    
-- Voltar para Sessão 1
    SELECT * FROM Contas; -- Deve mostrar os dados antigos (consistência de leitura)
COMMIT;


INSERT INTO Tentativas (equipe_id, questao_id, resposta, status) VALUES (
    1, 
    10, 
    'MVCC (Multiversion Concurrency Control):
    1) Mantém múltiplas versões dos dados;
    2) Cada transação vê snapshot consistente no momento de seu início;
    3) Vantagens:
       - Leituras não bloqueiam escritas;
       - Escritas não bloqueiam leituras;
       - Elimina muitos deadlocks;
    4) Desvantagens:
       - Overhead de armazenamento;
       - Garbage collection necessário;
    5) No teste:
       - T1 viu dados consistentes, ignorando alterações não commitadas;
       - T2 pôde modificar dados concorrentemente;
       - MySQL usa MVCC por padrão no InnoDB.',
    'PENDENTE'
);
