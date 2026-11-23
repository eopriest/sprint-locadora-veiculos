revisado e ajustado por Davi
-- Sprint Ágil de Refatoração de Banco de Dados
-- Tema 7: Locadora de Veículos  |  Compatível com SQLite
PRAGMA foreign_keys = ON;

-- Para rodar do zero:
DROP TABLE IF EXISTS Multas;
DROP TABLE IF EXISTS Manutencoes;
DROP TABLE IF EXISTS Locacoes;
DROP TABLE IF EXISTS Veiculos;
DROP TABLE IF EXISTS Clientes;
DROP TABLE IF EXISTS Frota;

------------------------------------------------------------------
-- PARTE 1 - ANTES: tabela Frota original (problema do cenário)
-- Dados do veículo, cliente, locação, manutenção e multa misturados.
-- Note: ABC1D23 e seus dados se repetem em várias linhas.
------------------------------------------------------------------
CREATE TABLE Frota (
    id_frota INTEGER PRIMARY KEY AUTOINCREMENT,
    placa TEXT, marca TEXT, modelo TEXT, ano INTEGER, status TEXT,
    cliente_nome TEXT, cliente_cpf TEXT, cliente_tel TEXT,
    data_retirada TEXT, data_prev_devolucao TEXT, data_devolucao TEXT, valor_locacao REAL,
    data_manutencao TEXT, desc_manutencao TEXT, custo_manutencao REAL,
    data_multa TEXT, desc_multa TEXT, valor_multa REAL
);

INSERT INTO Frota (placa, marca, modelo, ano, status, cliente_nome, cliente_cpf, cliente_tel,
                   data_retirada, data_prev_devolucao, data_devolucao, valor_locacao,
                   data_manutencao, desc_manutencao, custo_manutencao,
                   data_multa, desc_multa, valor_multa)
VALUES
('ABC1D23','Fiat','Argo',2022,'Disponível','Ana Souza','11122233344','11999990000',
 '2026-11-05','2026-11-08','2026-11-08',300, NULL,NULL,NULL, NULL,NULL,NULL),
('DEF4G56','Chevrolet','Onix',2023,'Manutenção','Bruno Lima','55566677788','11988880000',
 '2026-11-01','2026-11-04','2026-11-04',360, '2026-11-18','Troca de óleo e revisão',280, NULL,NULL,NULL),
('ABC1D23','Fiat','Argo',2022,'Disponível','Bruno Lima','55566677788','11988880000',
 '2026-11-10','2026-11-12','2026-11-12',200, NULL,NULL,NULL, NULL,NULL,NULL),
('GHI7J89','Toyota','Corolla',2021,'Alugado','Ana Souza','11122233344','11999990000',
 '2026-11-20','2026-11-25',NULL,750, NULL,NULL,NULL, '2026-11-22','Excesso de velocidade',195.23);

------------------------------------------------------------------
-- PARTE 2 - DEPOIS: estrutura normalizada (3FN)
------------------------------------------------------------------
CREATE TABLE Clientes (
    id_cliente INTEGER PRIMARY KEY AUTOINCREMENT,
    nome TEXT NOT NULL,
    cpf TEXT NOT NULL UNIQUE,
    telefone TEXT
);

CREATE TABLE Veiculos (
    id_veiculo INTEGER PRIMARY KEY AUTOINCREMENT,
    placa TEXT NOT NULL UNIQUE,
    marca TEXT NOT NULL,
    modelo TEXT NOT NULL,
    ano INTEGER,
    -- Decisão de desempenho: status guardado aqui (redundância controlada)
    -- para a busca de disponíveis não precisar varrer Locacoes/Manutencoes.
    status TEXT NOT NULL DEFAULT 'Disponível'
        CHECK (status IN ('Disponível','Alugado','Manutenção','Inativo'))
);

CREATE TABLE Locacoes (
    id_locacao INTEGER PRIMARY KEY AUTOINCREMENT,
    id_cliente INTEGER NOT NULL,
    id_veiculo INTEGER NOT NULL,
    data_retirada TEXT NOT NULL,
    data_prevista_devolucao TEXT NOT NULL,
    data_devolucao TEXT,
    valor_total REAL NOT NULL DEFAULT 0 CHECK (valor_total >= 0),
    status TEXT NOT NULL DEFAULT 'Aberta'
        CHECK (status IN ('Aberta','Concluída','Cancelada')),
    FOREIGN KEY (id_cliente) REFERENCES Clientes(id_cliente),
    FOREIGN KEY (id_veiculo) REFERENCES Veiculos(id_veiculo)
);

CREATE TABLE Manutencoes (
    id_manutencao INTEGER PRIMARY KEY AUTOINCREMENT,
    id_veiculo INTEGER NOT NULL,
    data_manutencao TEXT NOT NULL,
    descricao TEXT NOT NULL,
    custo REAL NOT NULL DEFAULT 0 CHECK (custo >= 0),
    status TEXT NOT NULL DEFAULT 'Concluída'
        CHECK (status IN ('Agendada','Em andamento','Concluída')),
    FOREIGN KEY (id_veiculo) REFERENCES Veiculos(id_veiculo)
);

-- Multa pertence a uma locação (o veículo é deduzido por ela: sem redundância).
CREATE TABLE Multas (
    id_multa INTEGER PRIMARY KEY AUTOINCREMENT,
    id_locacao INTEGER NOT NULL,
    data_multa TEXT NOT NULL,
    descricao TEXT NOT NULL,
    valor REAL NOT NULL CHECK (valor >= 0),
    status_pagamento TEXT NOT NULL DEFAULT 'Pendente'
        CHECK (status_pagamento IN ('Pendente','Paga','Contestada')),
    FOREIGN KEY (id_locacao) REFERENCES Locacoes(id_locacao)
);

------------------------------------------------------------------
-- PARTE 3 - Índices
------------------------------------------------------------------
CREATE INDEX idx_veiculos_status ON Veiculos(status);
CREATE INDEX idx_locacoes_veiculo_status ON Locacoes(id_veiculo, status);
CREATE INDEX idx_locacoes_datas ON Locacoes(data_retirada, data_prevista_devolucao);
CREATE INDEX idx_locacoes_cliente ON Locacoes(id_cliente);
CREATE INDEX idx_manutencoes_veiculo_data ON Manutencoes(id_veiculo, data_manutencao);
CREATE INDEX idx_manutencoes_veiculo_status
ON Manutencoes(id_veiculo, status);
CREATE INDEX idx_multas_locacao ON Multas(id_locacao);
-- Regra de negócio: no máximo 1 locação aberta por veículo.
CREATE UNIQUE INDEX ux_locacao_aberta ON Locacoes(id_veiculo) WHERE status = 'Aberta';

------------------------------------------------------------------
-- PARTE 4 - Migração DML: Frota -> novas tabelas
------------------------------------------------------------------
INSERT INTO Clientes (nome, cpf, telefone)
SELECT DISTINCT cliente_nome, cliente_cpf, cliente_tel
FROM Frota WHERE cliente_cpf IS NOT NULL;

-- Um veículo por placa, usando o status da linha mais recente.
INSERT INTO Veiculos (placa, marca, modelo, ano, status)
SELECT f.placa, f.marca, f.modelo, f.ano, f.status
FROM Frota f
WHERE f.id_frota = (SELECT MAX(id_frota) FROM Frota WHERE placa = f.placa);

INSERT INTO Locacoes (id_cliente, id_veiculo, data_retirada, data_prevista_devolucao,
                      data_devolucao, valor_total, status)
SELECT c.id_cliente, v.id_veiculo, f.data_retirada, f.data_prev_devolucao,
       f.data_devolucao, f.valor_locacao,
       CASE WHEN f.data_devolucao IS NULL THEN 'Aberta' ELSE 'Concluída' END
FROM Frota f
JOIN Clientes c ON c.cpf = f.cliente_cpf
JOIN Veiculos v ON v.placa = f.placa
WHERE f.data_retirada IS NOT NULL;

INSERT INTO Manutencoes (id_veiculo, data_manutencao, descricao, custo, status)
SELECT v.id_veiculo, f.data_manutencao, f.desc_manutencao, f.custo_manutencao,
       CASE WHEN v.status = 'Manutenção' THEN 'Em andamento' ELSE 'Concluída' END
FROM Frota f JOIN Veiculos v ON v.placa = f.placa
WHERE f.data_manutencao IS NOT NULL;

INSERT INTO Multas (id_locacao, data_multa, descricao, valor)
SELECT l.id_locacao, f.data_multa, f.desc_multa, f.valor_multa
FROM Frota f
JOIN Veiculos v ON v.placa = f.placa
JOIN Clientes c ON c.cpf = f.cliente_cpf
JOIN Locacoes l ON l.id_veiculo = v.id_veiculo AND l.id_cliente = c.id_cliente
               AND l.data_retirada = f.data_retirada
WHERE f.data_multa IS NOT NULL;

-- Conferência da migração (esperado: 2 clientes, 3 veículos, 4 locações, 1 manutenção, 1 multa)
SELECT (SELECT COUNT(*) FROM Clientes)    AS clientes,
       (SELECT COUNT(*) FROM Veiculos)    AS veiculos,
       (SELECT COUNT(*) FROM Locacoes)    AS locacoes,
       (SELECT COUNT(*) FROM Manutencoes) AS manutencoes,
       (SELECT COUNT(*) FROM Multas)      AS multas;

-- Depois de conferir, a tabela antiga pode ser removida:
-- DROP TABLE Frota;

------------------------------------------------------------------
-- PARTE 5 - Consultas de teste
------------------------------------------------------------------
-- 1. Veículos disponíveis
SELECT id_veiculo, placa, marca, modelo FROM Veiculos WHERE status = 'Disponível';

-- 2. Histórico de locações de um veículo
SELECT l.id_locacao, c.nome AS cliente, v.placa, l.data_retirada,
       l.data_prevista_devolucao, l.data_devolucao, l.status
FROM Locacoes l
JOIN Clientes c ON c.id_cliente = l.id_cliente
JOIN Veiculos v ON v.id_veiculo = l.id_veiculo
WHERE v.placa = 'ABC1D23'
ORDER BY l.data_retirada DESC;

-- 3. Manutenções por veículo
SELECT v.placa, v.modelo, m.data_manutencao, m.descricao, m.custo, m.status
FROM Manutencoes m JOIN Veiculos v ON v.id_veiculo = m.id_veiculo
ORDER BY m.data_manutencao DESC;

-- 4. Multas pendentes (veículo e cliente vêm pela locação)
SELECT mu.id_multa, v.placa, c.nome AS cliente, mu.data_multa, mu.descricao, mu.valor
FROM Multas mu
JOIN Locacoes l ON l.id_locacao = mu.id_locacao
JOIN Veiculos v ON v.id_veiculo = l.id_veiculo
JOIN Clientes c ON c.id_cliente = l.id_cliente
WHERE mu.status_pagamento = 'Pendente';

-- 5. Disponíveis sem locação aberta e sem manutenção pendente (checagem extra)
SELECT v.id_veiculo, v.placa, v.modelo
FROM Veiculos v
WHERE v.status = 'Disponível'
  AND NOT EXISTS (SELECT 1 FROM Locacoes l WHERE l.id_veiculo = v.id_veiculo AND l.status = 'Aberta')
  AND NOT EXISTS (SELECT 1 FROM Manutencoes m WHERE m.id_veiculo = v.id_veiculo
                  AND m.status IN ('Agendada','Em andamento'));

-- Exemplo: finalizar uma locação
-- UPDATE Locacoes SET data_devolucao = '2026-11-25', status = 'Concluída' WHERE id_locacao = 4;
-- UPDATE Veiculos SET status = 'Disponível' WHERE placa = 'GHI7J89';
