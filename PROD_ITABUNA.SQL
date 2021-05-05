PROMPT CREATE OR REPLACE PACKAGE dbamv.pkg_fnfi_dirf
CREATE OR REPLACE PACKAGE dbamv.pkg_fnfi_dirf IS
    PROCEDURE prc_dirf_pagamento(pCdMultiEmpresa IN number,
                                  pDtInicial IN date,
                                  pDtfinal IN date);

   end pkg_fnfi_dirf;
/

PROMPT CREATE OR REPLACE PACKAGE BODY dbamv.pkg_fnfi_dirf
CREATE OR REPLACE PACKAGE BODY dbamv.pkg_fnfi_dirf IS

    -- Importação da dirf pelo pagamento.

     PROCEDURE prc_dirf_pagamento(pCdMultiEmpresa IN number,
                                  pDtInicial IN date,
                                  pDtfinal IN date) IS
      -- Dados da empresa logada -
      Cursor cDadosEmpresa is
        Select  multi_empresas.cd_multi_empresa          cd_multi_empresa
              , multi_empresas.ds_multi_empresa          ds_multi_empresa
              , multi_empresas.ds_nome_contador          nm_contador
              , multi_empresas.cd_cgc                    cd_cgc
          from  dbamv.multi_empresas
         where ((cd_multi_empresa = pCdMultiEmpresa )
            or ( Dbamv.Pkg_Transacao_Entre_Empresas.IsFilial(cd_multi_empresa, pCdMultiEmpresa ) = 1 ));
       -- Cdigo dos Forncedores
      Cursor cFornecedores Is
        select f.tp_fornecedor  tp_fornecedor
            --   ,f.cd_fornecedor  cd_fornecedor
               ,f.nr_cgc_cpf  cd_fornecedor
               ,decode(f.tp_fornecedor, 'F', lpad(f.nr_cgc_cpf,11, 0), 'J', lpad(f.nr_cgc_cpf, 14, 0))	 nr_cgc_cpf
           from dbamv.con_pag cp
               ,dbamv.itcon_pag itcp
			   ,dbamv.tip_doc tdc  -- willian FINAN-2653
               ,dbamv.processo p
               ,dbamv.fornecedor f
         where cp.cd_processo = p.cd_processo
           and cp.cd_fornecedor  = f.cd_fornecedor
           and itcp.cd_con_pag = cp.cd_con_pag
		   AND cp.cd_tip_doc = tdc.cd_tip_doc     -- willian FINAN-2653
			--AND NVL(tdc.sn_retem_imposto,'S') = 'S'  -- willian FINAN-2653
           and p.cd_estrutural not in ('1.1.1.1.3','1.2.1.1.5','2.1.1.1.3','2.1.1.1.1')
           and cp.cd_fornecedor is not null
           and f.nr_cgc_cpf is not null
           and (( cp.cd_multi_empresa = pCdMultiEmpresa )
            or ( Dbamv.Pkg_Transacao_Entre_Empresas.IsFilial(cp.cd_multi_empresa, pCdMultiEmpresa ) = 1 ))
         group by f.tp_fornecedor
                 ,f.cd_fornecedor
                 ,f.nr_cgc_cpf
         order by 1;
         
      -- Cdigo dos Forncedores
      Cursor cFornecedor (pCPFCNPJ NUMBER) is
         Select f.nm_fornecedor
           from dbamv.fornecedor f
          WHERE f.nr_cgc_cpf =  pCPFCNPJ
          -- f.cd_fornecedor = pCPFCNPJ
            and rownum = 1;
      -- Lista de Detalhamento
      Cursor nBusca_Qtd_Det ( pAtividade VARCHAR2 ) is
         Select td.cd_detalhamento
           from dbamv.tip_detalhe td
          where td.cd_atividade = pAtividade
         order by 1;
      -- Lista de Atividade
      Cursor cBusca_Atividade is
       	Select td.cd_atividade
       	  from dbamv.tip_detalhe td
       	 where td.cd_atividade is not NULL
             AND td.cd_atividade IN ('0561','0588','5936','1889','3223','5565','2063','5706','3426','8053','6800','6813',
	  										         '5232','0924','3208','3277','5273','8468','5557','0422','0490','0481','9453','9478',
	  										         '5286','0473','9412','0610','9466','9427','5192','8045','5217','0916','8673','9385',
	  										         '3280','1708','5944','5204','6891','5928','1895','5952','5987','5979','5960')
      group by td.cd_atividade
      order by 1;
      -- valor do rendimento do fornecedor no ms
      cursor cMes_VlRendimento( pCPFCNPJ NUMBER, pTp_Fornecedor Varchar2, pMes varchar2, pAno varchar2 ) is
         select sum(( nvl(cp.vl_bruto_conta,0) +
                      nvl(cp.vl_desconto,0)) -
                      nvl(cp.vl_acrescimo,0))  vl_rendimento
         from dbamv.con_pag cp
             ,dbamv.processo p
			 ,dbamv.tip_doc tdc  -- willian FINAN-2653
             ,dbamv.fornecedor f
         where cp.cd_processo = p.cd_processo
           and cp.cd_fornecedor  = f.cd_fornecedor
		    AND cp.cd_tip_doc = tdc.cd_tip_doc     -- willian FINAN-2653
		--	AND NVL(tdc.sn_retem_imposto,'S') = 'S'  -- willian FINAN-2653
           and to_char(cp.dt_lancamento,'mm') = pMes
           and to_char(cp.dt_lancamento,'yyyy') = pAno
           and p.cd_estrutural not in ('1.1.1.1.3','1.2.1.1.5','2.1.1.1.3','2.1.1.1.1')
           and (( cp.cd_multi_empresa = pCdMultiEmpresa )
            or ( Dbamv.Pkg_Transacao_Entre_Empresas.IsFilial(cp.cd_multi_empresa, pCdMultiEmpresa ) = 1 ))
          -- and f.cd_fornecedor =  --pCPFCNPJ
           AND f.nr_cgc_cpf =  pCPFCNPJ
           and f.tp_fornecedor = pTp_Fornecedor
           and cp.cd_fornecedor is not null
           and cp.cd_previsao is null;
     -------------------------------------
      -- valor do rendimento do fornecedor-
      -------------------------------------
      cursor cVlRendimento( pCPFCNPJ NUMBER, pTp_Fornecedor Varchar2 ) is
---------------------------------------------------
-- Puxa todos os fornecedores com exceção
-- dos que foram tratados a parte
-- Fornecedores:380, 26748, 20967, 2918,16185, 474
---------------------------------------------------
SELECT dt_base,
       SUM(vl_rendimento) vl_rendimento
FROM   (SELECT To_number(To_char(dt_quitacao, 'mm')) dt_base,
               cd_con_pag,
               Decode(cd_estrutural, '1.2.1.1.2', SUM(Nvl(vl_prestacao, 0)),
                                     '1.2.1.1.3', SUM(Nvl(vl_prestacao, 0)),
                                     vl_detalhamento + vl_pago + (NVL(vl_desconto, 0) - Nvl(vl_acrescimo, 0)))  vl_rendimento
        FROM   (SELECT cp.cd_con_pag,
                       pg.cd_pagcon_pag,
                       pg.dt_pagamento                  dt_quitacao,
                       p.cd_estrutural,
                       pc.cd_prestacao_contas,
                       pc.vl_prestacao,
                       SUM(Nvl(tdp.vl_detalhamento, 0)) vl_detalhamento,
                       pg.vl_pago,
                       cp.vl_desconto,
                       cp.vl_acrescimo
                FROM   dbamv.con_pag cp,
                       dbamv.itcon_pag itcp,
                       dbamv.processo p,
                       dbamv.fornecedor f,
                       dbamv.prestacao_de_contas pc,
                       dbamv.tip_detcon_pag tdp,
                       dbamv.tip_detalhe td,
                       dbamv.pagcon_pag pg
                WHERE  cp.cd_processo = p.cd_processo
                       AND cp.cd_fornecedor = f.cd_fornecedor
                       AND itcp.cd_con_pag = cp.cd_con_pag
                       AND cp.cd_con_pag = tdp.cd_con_pag_pai (+)
                       AND tdp.cd_detalhamento = td.cd_detalhamento (+)
                       -- AND (tdp.cd_pagcon_pag IS NULL OR tdp.cd_pagcon_pag = pg.cd_pagcon_pag)
                       AND pg.cd_itcon_pag = itcp.cd_itcon_pag
                       AND pg.dt_estorno IS NULL
                       AND Trunc(pg.dt_pagamento) BETWEEN  trunc(pDtInicial) and trunc(pDtFinal)
                       AND p.cd_estrutural NOT IN ( '1.1.1.1.3',
                                                    '1.2.1.1.5',
                                                    '2.1.1.1.3',
                                                    '2.1.1.1.1' ,
                          '3.1.1.1.1')
                       AND ( ( cp.cd_multi_empresa = pCdMultiEmpresa )
                              OR (
       dbamv.pkg_transacao_entre_empresas.Isfilial(cp.cd_multi_empresa,
       pCdMultiEmpresa
       ) = 1 ) )
       AND f.cd_fornecedor = pCPFCNPJ
       AND f.cd_fornecedor NOT IN ( 380, 26748, 20967, 2918,
                                    16185, 474, 6515 ) --isaac
       AND f.tp_fornecedor = pTp_Fornecedor
       AND cp.cd_con_pag = pc.cd_con_pag (+)
       AND pc.cd_itcon_pag IS NULL
       AND cp.cd_fornecedor IS NOT NULL
       AND cp.cd_previsao IS NULL
       AND PG.tp_pagamento <> 'B'
       AND ( itcp.nr_parcela = 1
              OR ( itcp.nr_parcela >= 1
                   AND td.cd_atividade = '1708' ) )
                --and itcp.nr_parcela = 1
                GROUP  BY pg.dt_pagamento,
                          pg.cd_pagcon_pag,
                          cp.cd_con_pag,
                          p.cd_estrutural,
                          pc.cd_prestacao_contas,
                          pc.vl_prestacao,
                          pg.vl_pago,
                          cp.vl_desconto,
                          cp.vl_acrescimo)
        GROUP  BY dt_quitacao,
                  cd_con_pag,
                  cd_estrutural,
                  vl_prestacao,
                  vl_detalhamento,
                  vl_pago,
                  vl_desconto,
                  vl_acrescimo)
GROUP  BY dt_base
UNION ALL
---------------------------------------------------
-- Calculo epecífico Fornec 26748
---------------------------------------------------
SELECT dt_base,
       SUM(vl_rendimento) vl_rendimento
FROM   (SELECT To_number(To_char(dt_pagamento, 'mm')) DT_BASE,
               cd_con_pag,
               vl_rendimento_pag                      vl_rendimento
        FROM   (SELECT pg.dt_pagamento dt_pagamento,
                       cp.cd_con_pag,
                       ( SUM(Nvl(pg.vl_pago, 0) +
                             Nvl(pg.vl_desconto, 0) -
                             Nvl(pg.vl_acrescimo, 0) +
                             Nvl(cp.vl_desconto, 0) -
                             Nvl(cp.vl_acrescimo, 0) +
                              Decode (it.nr_parcela, 1,
                                    Nvl (Det_imp.vl_detalhe, 0 ), 0) + Nvl(pg.vl_imposto, 0))) vl_rendimento_pag --MFSS
                FROM   dbamv.con_pag cp,
                       dbamv.itcon_pag it,
                       dbamv.pagcon_pag pg,
                       dbamv.processo p,
                       dbamv.fornecedor f,
                       dbamv.plano_contas pl,
                       (SELECT tdc.cd_con_pag_pai,
                               SUM(Nvl(tdc.vl_detalhamento, 0)) vl_detalhe
                        FROM   dbamv.tip_detcon_pag tdc,
                               dbamv.tip_detalhe td
                        WHERE  tdc.cd_pagcon_pag IS NULL
                               AND tdc.cd_detalhamento = td.cd_detalhamento
                               AND td.tp_data <> 'P'
                        GROUP  BY tdc.cd_con_pag_pai) Det_imp
                WHERE  cp.cd_processo = p.cd_processo
                       AND cp.cd_fornecedor = f.cd_fornecedor
                       AND cp.cd_reduzido = pl.cd_reduzido (+)
                       AND cp.cd_con_pag = det_imp.cd_con_pag_pai(+)
                       -- AND it.nr_parcela =1
                       AND it.cd_con_pag = cp.cd_con_pag
                       AND pg.tp_pagamento <> 'B'
                       --AND f.cd_fornecedor = pCPFCNPJ
                       AND f.cd_fornecedor = 26748
                       AND f.cd_fornecedor = pCPFCNPJ
                       AND f.tp_fornecedor = pTp_Fornecedor
                       AND it.cd_itcon_pag = pg.cd_itcon_pag
                       -- and to_char(cp.dt_emissao,'yyyy') = to_char(pg.dt_pagamento,'yyyy')
                       AND p.cd_estrutural NOT IN ( '1.1.1.1.3',
                                                    '1.2.1.1.5',
                                                    '2.1.1.1.3',
                                                    '2.1.1.1.1',
                                                    '1.2.1.1.2')
                       AND cp.cd_previsao IS NULL
                       AND pg.cd_pagcon_pag = (SELECT Min (cd_pagcon_pag)
                                               FROM   dbamv.pagcon_pag
                                               WHERE cd_itcon_pag = Pg.cd_itcon_pag
                                               AND dt_estorno IS NULL)
                       AND ( ( cp.cd_multi_empresa = pCdMultiEmpresa )
                        OR (dbamv.pkg_transacao_entre_empresas.Isfilial(cp.cd_multi_empresa, pCdMultiEmpresa) = 1 ) )
                       AND Trunc(pg.dt_pagamento) BETWEEN trunc(pDtInicial) and trunc(pDtFinal)
                GROUP  BY pg.dt_pagamento,
                          cp.cd_con_pag,
                          Decode(it.nr_parcela, 1, Nvl(Det_imp.vl_detalhe, 0),0)))
GROUP  BY dt_base

--------------------------------------
-- Calculo para fornecedor MATTEDI
-- e também fornecedores 16185 e 474
-- incluídos a pedido de Daniel
--------------------------------------
UNION ALL
SELECT dt_base,
       SUM(vl_rendimento) vl_rendimento
FROM   (SELECT To_number(To_char(dt_pagamento, 'mm')) DT_BASE,
               cd_con_pag,
               vl_rendimento_pag                      vl_rendimento
        FROM   (SELECT pg.dt_pagamento   dt_pagamento,
                       cp.cd_con_pag,
                       Round(( (( ( ( SUM(Nvl(pg.vl_pago, 0) +
                                          Nvl(pg.vl_desconto, 0) -
                                          Nvl(pg.vl_acrescimo, 0)+ Nvl(pg.vl_imposto, 0))) * 100) / 0.9185 )) / 100 ), 2) vl_rendimento_pag
                FROM   dbamv.con_pag cp,
                       dbamv.itcon_pag it,
                       dbamv.pagcon_pag pg,
                       dbamv.processo p,
                       dbamv.fornecedor f,
                       dbamv.plano_contas pl
                WHERE  cp.cd_processo = p.cd_processo
                       AND cp.cd_fornecedor = f.cd_fornecedor
                       AND cp.cd_reduzido = pl.cd_reduzido (+)
                       AND pg.dt_estorno IS NULL
                       AND it.cd_con_pag = cp.cd_con_pag
                       AND it.cd_itcon_pag = pg.cd_itcon_pag
                       AND pg.tp_pagamento <> 'B'
                       AND p.cd_estrutural NOT IN ( '1.1.1.1.3',
                                                    '1.2.1.1.5',
                                                    '2.1.1.1.3',
                                                    '2.1.1.1.1',
                                                    '1.2.1.1.2')
                       AND cp.cd_previsao IS NULL
                       --AND f.cd_fornecedor = pCPFCNPJ
                       AND f.cd_fornecedor IN( 380, 16185, 474 )
                       AND f.cd_fornecedor = pCPFCNPJ
                       AND f.tp_fornecedor = pTp_Fornecedor
                       AND pg.cd_pagcon_pag <> (SELECT Min (cd_pagcon_pag)
                                                FROM   dbamv.pagcon_pag
                                                WHERE  CD_ITCON_PAG = Pg.cd_itcon_pag
                                                AND dt_estorno IS NULL)
                       AND ( ( cp.cd_multi_empresa = pCdMultiEmpresa ) OR (dbamv.pkg_transacao_entre_empresas.Isfilial(cp.cd_multi_empresa,pCdMultiEmpresa) = 1 ) )
                       AND Trunc(pg.dt_pagamento) BETWEEN  trunc(pDtInicial) and trunc(pDtFinal)
                GROUP  BY pg.dt_pagamento,
                          cp.cd_con_pag))
GROUP  BY dt_base

----------------------------------------
-- Calculo para fornecedor 20967 e 2918
----------------------------------------
UNION ALL
SELECT dt_base,
       SUM(vl_rendimento) vl_rendimento
FROM   (SELECT To_number(To_char(dt_quitacao, 'mm')) dt_base,
               cd_con_pag,
               Decode(cd_estrutural, '1.2.1.1.2', SUM(Nvl(vl_prestacao, 0)),
                                     '1.2.1.1.3', SUM(Nvl(vl_prestacao, 0)),
                                     vl_detalhamento + vl_pago + (Nvl(vl_desconto, 0) - Nvl(vl_acrescimo, 0)))vl_rendimento
        FROM   (SELECT cp.cd_con_pag,
                       pg.cd_pagcon_pag,
                       pg.dt_pagamento          dt_quitacao,
                       p.cd_estrutural,
                       pc.cd_prestacao_contas,
                       pc.vl_prestacao,
                       SUM(tdp.vl_detalhamento) vl_detalhamento,
                       pg.vl_pago,
                       cp.vl_desconto,
                       cp.vl_acrescimo
                FROM   dbamv.con_pag cp,
                       dbamv.itcon_pag itcp,
                       dbamv.processo p,
                       dbamv.fornecedor f,
                       dbamv.prestacao_de_contas pc,
                       dbamv.tip_detcon_pag tdp,
                       dbamv.tip_detalhe td,
                       dbamv.pagcon_pag pg
                WHERE  cp.cd_processo = p.cd_processo
                       AND cp.cd_fornecedor = f.cd_fornecedor
                       AND itcp.cd_con_pag = cp.cd_con_pag
                       AND cp.cd_con_pag = tdp.cd_con_pag_pai
                       AND tdp.cd_detalhamento = td.cd_detalhamento (+)
                       AND ( tdp.cd_pagcon_pag IS NULL
                              OR tdp.cd_pagcon_pag = pg.cd_pagcon_pag )
                       AND pg.cd_itcon_pag = itcp.cd_itcon_pag
                       AND pg.dt_estorno IS NULL
                       AND Trunc(pg.dt_pagamento) BETWEEN trunc(pDtInicial) and trunc(pDtFinal)
                       AND p.cd_estrutural NOT IN ( '1.1.1.1.3',
                                                    '1.2.1.1.5',
                                                    '2.1.1.1.3',
                                                    '2.1.1.1.1')
                       AND ( ( cp.cd_multi_empresa = pCdMultiEmpresa )
                          OR (dbamv.pkg_transacao_entre_empresas.Isfilial(cp.cd_multi_empresa,pCdMultiEmpresa) = 1 ) )
       AND ( f.cd_fornecedor = 20967
              OR f.cd_fornecedor = 2918 )
       AND f.nr_cgc_cpf IN (SELECT nr_cgc_cpf
                            FROM   dbamv.fornecedor
                            WHERE  cd_fornecedor = pCPFCNPJ) --isaac
       AND f.tp_fornecedor = pTp_Fornecedor
       AND cp.cd_con_pag = pc.cd_con_pag (+)
       AND pc.cd_itcon_pag IS NULL
       AND cp.cd_fornecedor IS NOT NULL
       AND cp.cd_previsao IS NULL
       AND PG.tp_pagamento <> 'B'
       AND ( itcp.nr_parcela = 1
              OR ( itcp.nr_parcela >= 1
                   AND td.cd_atividade = '1708' ) )
                --and itcp.nr_parcela = 1
                GROUP  BY pg.dt_pagamento,
                          pg.cd_pagcon_pag,
                          cp.cd_con_pag,
                          p.cd_estrutural,
                          pc.cd_prestacao_contas,
                          pc.vl_prestacao,
                          pg.vl_pago,
                          cp.vl_desconto,
                          cp.vl_acrescimo)
        GROUP  BY dt_quitacao,
                  cd_con_pag,
                  cd_estrutural,
                  vl_prestacao,
                  vl_detalhamento,
                  vl_pago,
                  vl_desconto,
                  vl_acrescimo)
GROUP  BY dt_base

---------------------------------------------------------
-- Tratamento para as contas de repasse médico
---------------------------------------------------------
union all
  SELECT dt_base,
       SUM(vl_rendimento) vl_rendimento
  FROM   (SELECT To_number(To_char(dt_pagamento, 'mm')) DT_BASE,
               cd_con_pag,
               vl_rendimento_pag                      vl_rendimento
        FROM   (SELECT pg.dt_pagamento dt_pagamento,
                       cp.cd_con_pag,
                       ( SUM(Nvl(pg.vl_pago, 0) + Nvl(pg.vl_desconto, 0) -
                             Nvl(pg.vl_acrescimo, 0) +
                                   Nvl(cp.vl_desconto, 0) -
                             Nvl(cp.vl_acrescimo, 0) +
                                   Decode (it.nr_parcela, 1,
                                   Nvl (Det_imp.vl_detalhe, 0),0) + Nvl(pg.vl_imposto, 0))) vl_rendimento_pag --MFSS
                FROM   dbamv.con_pag cp,
                       dbamv.itcon_pag it,
                       dbamv.pagcon_pag pg,
                       dbamv.processo p,
                       dbamv.fornecedor f,
                       dbamv.plano_contas pl,
                       (SELECT tdc.cd_con_pag_pai,
                               SUM(Nvl(tdc.vl_detalhamento, 0)) vl_detalhe
                        FROM   dbamv.tip_detcon_pag tdc,
                               dbamv.tip_detalhe td
                        WHERE  tdc.cd_pagcon_pag IS NULL
                               AND tdc.cd_detalhamento = td.cd_detalhamento
                               AND td.tp_data <> 'P'
                        GROUP  BY tdc.cd_con_pag_pai) Det_imp
                WHERE  cp.cd_processo = p.cd_processo
                       AND cp.cd_fornecedor = f.cd_fornecedor
                       AND cp.cd_reduzido = pl.cd_reduzido (+)
                       AND cp.cd_con_pag = det_imp.cd_con_pag_pai(+)
                       -- AND it.nr_parcela =1
                       AND it.cd_con_pag = cp.cd_con_pag
                       -- AND f.cd_fornecedor = pCPFCNPJ
                       AND f.nr_cgc_cpf IN (SELECT nr_cgc_cpf
                                            FROM   dbamv.fornecedor
                                            WHERE  cd_fornecedor = pCPFCNPJ)
                       AND f.tp_fornecedor = pTp_Fornecedor
                       AND it.cd_itcon_pag = pg.cd_itcon_pag
                       -- and to_char(cp.dt_emissao,'yyyy') = to_char(pg.dt_pagamento,'yyyy')
                       AND p.cd_estrutural = '3.1.1.1.1'
                       AND PG.tp_pagamento <> 'B'
                       AND cp.cd_previsao IS NULL
                       AND pg.cd_pagcon_pag = (SELECT Min (cd_pagcon_pag)
                                               FROM   dbamv.pagcon_pag
                                               WHERE  cd_itcon_pag = Pg.cd_itcon_pag
                                               AND dt_estorno IS NULL)
                       AND ( ( cp.cd_multi_empresa = pCdMultiEmpresa )
                       OR (dbamv.pkg_transacao_entre_empresas.Isfilial(cp.cd_multi_empresa, pCdMultiEmpresa) = 1) )
                      AND Trunc(pg.dt_pagamento) BETWEEN trunc(pDtInicial) and trunc(pDtFinal)
                GROUP  BY pg.dt_pagamento,
                          cp.cd_con_pag,
                          Decode(it.nr_parcela, 1, Nvl(Det_imp.vl_detalhe, 0),
                                                0)
                UNION ALL
                SELECT pg.dt_pagamento                  dt_pagamento,
                       cp.cd_con_pag,
                       ( SUM(Nvl(pg.vl_pago, 0) + Nvl(pg.vl_desconto, 0) -
                             Nvl(pg.vl_acrescimo, 0) +
                               Nvl(pg.vl_imposto, 0)) ) vl_rendimento_pag
                FROM   dbamv.con_pag cp,
                       dbamv.itcon_pag it,
                       dbamv.pagcon_pag pg,
                       dbamv.processo p,
                       dbamv.fornecedor f,
                       dbamv.plano_contas pl
                WHERE  cp.cd_processo = p.cd_processo
                       AND cp.cd_fornecedor = f.cd_fornecedor
                       AND cp.cd_reduzido = pl.cd_reduzido (+)
                       AND pg.dt_estorno IS NULL
                       AND it.cd_con_pag = cp.cd_con_pag
                       AND it.cd_itcon_pag = pg.cd_itcon_pag
                       AND p.cd_estrutural = '3.1.1.1.1'
                       AND cp.cd_previsao IS NULL
                       --AND f.cd_fornecedor = pCPFCNPJ
                       AND f.nr_cgc_cpf IN (SELECT nr_cgc_cpf
                                            FROM   dbamv.fornecedor
                                            WHERE  cd_fornecedor = pCPFCNPJ)
                       AND f.tp_fornecedor = pTp_Fornecedor
                       AND PG.tp_pagamento <> 'B'
                       AND pg.cd_pagcon_pag <> (SELECT Min (cd_pagcon_pag)
                                                FROM   dbamv.pagcon_pag
                                                WHERE
                           cd_itcon_pag = Pg.cd_itcon_pag
                           AND dt_estorno IS NULL)
                       AND ( ( cp.cd_multi_empresa = pCdMultiEmpresa )
                       OR (dbamv.pkg_transacao_entre_empresas.Isfilial(cp.cd_multi_empresa,pCdMultiEmpresa) = 1) )
                       AND Trunc(pg.dt_pagamento) BETWEEN trunc(pDtInicial) and trunc(pDtFinal)
                GROUP  BY pg.dt_pagamento,
                          cp.cd_con_pag))
      GROUP  BY dt_base;


      -- Valor do Detalhamento
      Cursor cDetalhamento_Cont( pCPFCNPJ NUMBER, pAtividade VARCHAR2 ) IS  --pmva
      select sum(qtd) qtd from (
     select count(*) qtd
		 From dbamv.con_pag cp
		     ,dbamv.itcon_pag it
		     ,dbamv.tip_detcon_pag tdp
		     ,dbamv.tip_detalhe td
		     ,dbamv.fornecedor f
		     ,( select
		          pagcon_pag.cd_itcon_pag,
		          max(dt_pagamento) dt_pagamento
		        from
		          dbamv.pagcon_pag,
		          dbamv.itcon_pag,
		          dbamv.con_pag cp2
		        where 1=1
		          and pagcon_pag.cd_itcon_pag = itcon_pag.cd_itcon_pag
		          and itcon_pag.cd_con_pag = cp2.cd_con_pag
		          and dt_estorno is null
		          AND trunc(pagcon_pag.dt_pagamento) between trunc(pDtInicial) and trunc(pDtFinal)
		     group by pagcon_pag.cd_itcon_pag) pg

		Where cp.cd_con_pag       = it.cd_con_pag
		  and it.cd_con_pag       = tdp.cd_con_pag_pai
		  and it.cd_itcon_pag     =  pg.cd_itcon_pag
		  and cp.cd_fornecedor    = f.cd_fornecedor
		  and tdp.cd_detalhamento = td.cd_detalhamento
		  AND td.tp_data <> 'P'
		   and	( ( cp.cd_multi_empresa = pCdMultiEmpresa ) or
               ( Dbamv.Pkg_Transacao_Entre_Empresas.IsFilial(cp.cd_multi_empresa, pCdMultiEmpresa ) = 1))

      --and cp.cd_fornecedor = 2918 --pCPFCNPJ
      AND f.nr_cgc_cpf =  pCPFCNPJ
      and td.cd_atividade  = pAtividade
		  --and it.nr_parcela = 1
		  --and to_char(cp.dt_emissao,'yyyy') = to_char(pg.dt_pagamento,'yyyy')

      UNION ALL

    select Count(*)
		 From dbamv.con_pag cp
		     ,dbamv.itcon_pag it
		     ,dbamv.tip_detcon_pag tdp
		     ,dbamv.tip_detalhe td
		     ,dbamv.fornecedor f
         ,dbamv.pagcon_pag pg
		Where cp.cd_con_pag       = it.cd_con_pag
		  and it.cd_con_pag       = tdp.cd_con_pag_pai
		  and it.cd_itcon_pag     =  pg.cd_itcon_pag
		  and cp.cd_fornecedor    = f.cd_fornecedor
      AND pg.cd_pagcon_pag   = tdp.cd_pagcon_pag
      AND td.tp_data = 'P'
		  and tdp.cd_detalhamento = td.cd_detalhamento
		   and	( ( cp.cd_multi_empresa = pCdMultiEmpresa ) or
               ( Dbamv.Pkg_Transacao_Entre_Empresas.IsFilial(cp.cd_multi_empresa, pCdMultiEmpresa ) = 1))
	     --   and trunc(it.dt_quitacao) between trunc(pDtInicial) and trunc(pDtFinal)
          and trunc(pg.dt_pagamento) between trunc(pDtInicial) and trunc(pDtFinal)
      --and cp.cd_fornecedor = 2918 --pCPFCNPJ
      AND f.nr_cgc_cpf =  pCPFCNPJ
           and td.cd_atividade  = pAtividade);


      Cursor cDetalhamento( pCPFCNPJ NUMBER, pAtividade VARCHAR2 ) IS     --pmva
      
     	select distinct cp.cd_con_pag        cd_con_pag,
                td.tp_data           tp_data
             ,cp.dt_lancamento     dt_lancamento
             ,dt_det.dt_pagamento       dt_pagamento
             ,tdp.cd_con_pag_filho
             ,Sum(nvl(tdp.vl_detalhamento, 0))  vl_detalhamento
             ,td.cd_atividade      cd_atividade
             ,td.tp_detalhamento   tp_detalhamento
        From dbamv.con_pag cp
            ,dbamv.itcon_pag it
            ,dbamv.tip_detcon_pag tdp
            ,dbamv.tip_detalhe td
            ,(SELECT p.cd_pagcon_pag, i.cd_con_pag, p.dt_pagamento dt_pagamento
                 from dbamv.itcon_pag i
                     ,dbamv.pagcon_pag p
                Where i.cd_itcon_pag = p.cd_itcon_pag
                and p.tp_pagamento <> 'B'
            and p.dt_estorno is null
               ) dt_det
       Where cp.cd_con_pag       = it.cd_con_pag
         and it.cd_con_pag       = tdp.cd_con_pag_pai
         and tdp.cd_detalhamento = td.cd_detalhamento
         and it.cd_con_pag       = dt_det.cd_con_pag
         AND (tdp.cd_pagcon_pag IS NULL OR tdp.cd_pagcon_pag = dt_det.cd_pagcon_pag)
         and (( cp.cd_multi_empresa = pCdMultiEmpresa )
          or ( Dbamv.Pkg_Transacao_Entre_Empresas.IsFilial(cp.cd_multi_empresa, pCdMultiEmpresa ) = 1 ))
         and trunc(dt_det.dt_pagamento) between trunc(pDtInicial) and trunc(pDtFinal)
        --and trunc(it.dt_quitacao) between trunc(pDtInicial) and trunc(pDtFinal)
     and cp.cd_fornecedor NOT in (380,20967,2918,26748,16185,474 )
         and cp.cd_fornecedor = pCPFCNPJ
         and td.cd_atividade  = pAtividade
         AND (
        it.nr_parcela = 1
        OR (
          it.nr_parcela >= 1
          AND td.cd_atividade = '1708'
          )
        )
       --  and it.nr_parcela = 1
          group by cp.cd_con_pag
                  ,td.tp_data
                  ,cp.dt_lancamento
                  ,dt_det.dt_pagamento
                  ,tdp.cd_con_pag_filho
                  ,td.cd_atividade
                  ,td.tp_detalhamento
    UNION ALL
    -- Cursor cDetalhamento( pCPFCNPJ NUMBER, pAtividade VARCHAR2 ) is
        select distinct cp.cd_con_pag        cd_con_pag,
                td.tp_data           tp_data
             ,cp.dt_lancamento     dt_lancamento
             ,pg.dt_pagamento       dt_pagamento
             ,tdp.cd_con_pag_filho
             ,Decode(pAtividade,
                  1708,
                  Trunc((trunc(((pg.vl_pago * 100) / 0.9185)/ 100,2)* 0.015),2),
                  5952,
                  Trunc((trunc(((pg.vl_pago * 100) / 0.9185)/ 100,2)* 0.0465),2))  vl_detalhamento -- Isaac
             ,td.cd_atividade      cd_atividade
             ,td.tp_detalhamento   tp_detalhamento
       From dbamv.con_pag cp
         ,dbamv.itcon_pag it
         ,dbamv.tip_detcon_pag tdp
         ,dbamv.tip_detalhe td
         ,dbamv.fornecedor f
         ,( select
              pagcon_pag.cd_itcon_pag,
              pagcon_pag.dt_pagamento,
              pagcon_pag.vl_pago
            from
              dbamv.pagcon_pag,
              dbamv.itcon_pag,
              dbamv.con_pag cp2
            where 1=1
              and pagcon_pag.cd_itcon_pag = itcon_pag.cd_itcon_pag
              and itcon_pag.cd_con_pag = cp2.cd_con_pag
              and dt_estorno is null
              AND pagcon_pag.dt_pagamento between trunc(pDtInicial) and trunc(pDtFinal)
            group by pagcon_pag.cd_itcon_pag,
                       pagcon_pag.vl_pago,
                       pagcon_pag.dt_pagamento
                        ) pg
    Where cp.cd_con_pag       = it.cd_con_pag
      and it.cd_con_pag       = tdp.cd_con_pag_pai
      and it.cd_itcon_pag     =  pg.cd_itcon_pag
      and cp.cd_fornecedor    = f.cd_fornecedor
      AND td.tp_data <> 'P'
      AND td.tp_detalhamento <> 'N'
      and tdp.cd_detalhamento = td.cd_detalhamento
       and (( cp.cd_multi_empresa = pCdMultiEmpresa )
                  or (Dbamv.Pkg_Transacao_Entre_Empresas.IsFilial(cp.cd_multi_empresa, pCdMultiEmpresa ) = 1 ))
      --and  f.cd_fornecedor  = 2918 --pCPFCNPJ
     AND f.cd_fornecedor IN(380,16185,474)
      AND f.cd_fornecedor =  pCPFCNPJ
      and td.cd_atividade  = pAtividade
     --and it.nr_parcela = 1
     -- and to_char(cp.dt_emissao,'yyyy') = to_char(pg.dt_pagamento,'yyyy')
      and it.tp_quitacao in ('Q','P') --Quitado e Parcialmente quitado   )

/*parte*/
  union all

  select distinct cp.cd_con_pag        cd_con_pag,
                td.tp_data           tp_data
             ,cp.dt_lancamento     dt_lancamento
             ,dt_det.dt_pagamento       dt_pagamento
             ,tdp.cd_con_pag_filho
             ,Sum(nvl(tdp.vl_detalhamento, 0))  vl_detalhamento
             ,td.cd_atividade      cd_atividade
             ,td.tp_detalhamento   tp_detalhamento
        From dbamv.con_pag cp
            ,dbamv.itcon_pag it
            ,dbamv.tip_detcon_pag tdp
            ,dbamv.tip_detalhe td
      ,dbamv.fornecedor f
            ,(SELECT p.cd_pagcon_pag, i.cd_con_pag, p.dt_pagamento dt_pagamento
                 from dbamv.itcon_pag i
                     ,dbamv.pagcon_pag p
                Where i.cd_itcon_pag = p.cd_itcon_pag
                and p.tp_pagamento <> 'B'
            and p.dt_estorno is null
               ) dt_det
       Where cp.cd_con_pag       = it.cd_con_pag
         and it.cd_con_pag       = tdp.cd_con_pag_pai
         and tdp.cd_detalhamento = td.cd_detalhamento
         and it.cd_con_pag       = dt_det.cd_con_pag
     and cp.cd_fornecedor = f.cd_fornecedor
         AND (tdp.cd_pagcon_pag IS NULL OR tdp.cd_pagcon_pag = dt_det.cd_pagcon_pag)
         and (( cp.cd_multi_empresa = pCdMultiEmpresa )
          or ( Dbamv.Pkg_Transacao_Entre_Empresas.IsFilial(cp.cd_multi_empresa, pCdMultiEmpresa ) = 1 ))
         and trunc(dt_det.dt_pagamento) between trunc(pDtInicial) and trunc(pDtFinal)
        --and trunc(it.dt_quitacao) between trunc(pDtInicial) and trunc(pDtFinal)
         and (cp.cd_fornecedor = 20967 or cp.cd_fornecedor = 2918 )
     AND f.nr_cgc_cpf  IN (select nr_cgc_cpf from dbamv.fornecedor where cd_fornecedor = pCPFCNPJ)  --isaac
         and td.cd_atividade  = pAtividade
         AND (
        it.nr_parcela = 1
        OR (
          it.nr_parcela >= 1
          AND td.cd_atividade = '1708'
          )
        )
       --  and it.nr_parcela = 1
          group by cp.cd_con_pag
                  ,td.tp_data
                  ,cp.dt_lancamento
                  ,dt_det.dt_pagamento
                  ,tdp.cd_con_pag_filho
                  ,td.cd_atividade
                  ,td.tp_detalhamento
--parte radio
union all
select distinct cp.cd_con_pag        cd_con_pag,
                td.tp_data           tp_data
             ,cp.dt_lancamento     dt_lancamento
             ,pg.dt_pagamento       dt_pagamento
             ,tdp.cd_con_pag_filho
             ,Sum(nvl(tdp.vl_detalhamento, 0))  vl_detalhamento
             ,td.cd_atividade      cd_atividade
             ,td.tp_detalhamento   tp_detalhamento
     From dbamv.con_pag cp
         ,dbamv.itcon_pag it
         ,dbamv.tip_detcon_pag tdp
         ,dbamv.tip_detalhe td
         ,dbamv.fornecedor f
         ,dbamv.pagcon_pag pg
    Where cp.cd_con_pag       = it.cd_con_pag
      and it.cd_con_pag       = tdp.cd_con_pag_pai
      and it.cd_itcon_pag     =  pg.cd_itcon_pag
      and cp.cd_fornecedor    = f.cd_fornecedor
      AND pg.cd_pagcon_pag   = tdp.cd_pagcon_pag
      AND td.tp_data = 'P'
      and tdp.cd_detalhamento = td.cd_detalhamento
      and PG.tp_pagamento <> 'B'
      and (( cp.cd_multi_empresa = pCdMultiEmpresa )
                  or (Dbamv.Pkg_Transacao_Entre_Empresas.IsFilial(cp.cd_multi_empresa, pCdMultiEmpresa ) = 1 ))
      AND pg.dt_pagamento between trunc(pDtInicial) and trunc(pDtFinal)
      AND td.tp_detalhamento <> 'N'
      --and   f.cd_fornecedor  = 2918-- pCPFCNPJ
      and (cp.cd_fornecedor = 26748 )
     AND f.nr_cgc_cpf  IN (select nr_cgc_cpf from dbamv.fornecedor where cd_fornecedor = pCPFCNPJ)  --isaac
      and it.tp_quitacao in ('Q','P') --Quitado e Parcialmente quitado
      and td.cd_atividade  = pAtividade
      GROUP BY cp.cd_con_pag,
               td.tp_data,
               cp.dt_lancamento,
               pg.dt_pagamento,
               tdp.cd_con_pag_filho,
               td.cd_atividade,
               td.tp_detalhamento;



      cursor cDetalhamentoInss( pCPFCNPJ NUMBER) is
         select td.tp_data           tp_data
               ,cp.dt_lancamento     dt_lancamento
               ,it.dt_quitacao       dt_pagamento
               ,cp.cd_con_pag        cd_con_pag
               ,tdp.cd_con_pag_filho -- PDA 277527 27/03/2009 - Eudes Gomes
               ,tdp.vl_detalhamento  vl_detalhamento
               ,td.cd_atividade      cd_atividade
               ,td.tp_detalhamento   tp_detalhamento
          From dbamv.con_pag cp
			  ,dbamv.tip_doc tdc  -- willian FINAN-2653
              ,dbamv.itcon_pag it
              ,dbamv.tip_detcon_pag tdp
              ,dbamv.tip_detalhe td
              ,dbamv.fornecedor f
         Where cp.cd_con_pag       = it.cd_con_pag
           and it.cd_con_pag       = tdp.cd_con_pag_pai
		   AND cp.cd_tip_doc = tdc.cd_tip_doc     -- willian FINAN-2653
		  -- AND NVL(tdc.sn_retem_imposto,'S') = 'S'  -- willian FINAN-2653
           and tdp.cd_detalhamento = td.cd_detalhamento
           and (( cp.cd_multi_empresa = pCdMultiEmpresa )
            or ( Dbamv.Pkg_Transacao_Entre_Empresas.IsFilial(cp.cd_multi_empresa, pCdMultiEmpresa ) = 1 ))
           and trunc(it.dt_quitacao) between trunc(pDtInicial) and trunc(pDtFinal)
         --  and cp.cd_fornecedor = 2918--pCPFCNPJ
         AND f.cd_fornecedor = cp.cd_fornecedor
         AND f.nr_cgc_cpf =  pCPFCNPJ
           and td.tp_detalhamento = 'N'
           and it.nr_parcela = 1;
      -- CURSOR RESPONVEL POR TRAZER E ORGANIZAR DADOS DA TABELA TEMPORRIA DA DIRF.
      --------------------------------------------------------------------------------
      CURSOR C_TEMP_DIRF IS
       		select cd_atividade,
                  nr_cgc_cpf,
                  tp_fornec,
                  registro,
                  valor,
                  registro2,
                  nm_fornecedor,
                  registro3
       		  from DBAMV.TMPMV_FNFI_GERACAO_DIRF
         order by cd_atividade, nr_cgc_cpf;
      -- CURSOR RESPONVEL POR TRAZER DADOS DA EMPRESA (HOSPITAL)
      -----------------------------------------------------------------------
      Cursor cEMPRESA IS
       	select nvl(cd_cgc,0), nvl(ds_multi_empresa,' ')
       	  from dbamv.multi_empresas
       	 where cd_multi_empresa = pCdMultiEmpresa;
      ------------------------------------------------------------------
      Cursor Busca_IR( pCPFCNPJ NUMBER ) is
        Select sum( tdcp.vl_detalhamento )
          from dbamv.fornecedor f,
               dbamv.con_pag cp,
			          dbamv.tip_doc td,  -- willian FINAN-2653
               dbamv.tip_detcon_pag tdcp,
               dbamv.tip_detalhe tpd
         where cp.cd_multi_empresa = pCdMultiEmpresa
--           and f.cd_fornecedor = pCPFCNPJ
        and f.nr_cgc_cpf = pCPFCNPJ
		    AND cp.cd_tip_doc = td.cd_tip_doc     -- willian FINAN-2653
			--AND NVL(td.sn_retem_imposto,'S') = 'S'  -- willian FINAN-2653
           and cp.cd_fornecedor = f.cd_fornecedor
           and tdcp.cd_con_pag_pai(+) = cp.cd_con_pag
           and tpd.tp_detalhamento in ('F','J')
           and tdcp.cd_detalhamento = tpd.cd_detalhamento
           and tdcp.vl_detalhamento > 0
           and trunc(cp.dt_lancamento) between trunc(pDtInicial) and trunc(pDtFinal);
      	------------------------------------------------------------------
     	-- REGISTRO TIPO 1 (INFORMAES DO DECLARANTE)
     	------------------------------------------------------------------
     	vTP123nr_seq													varchar2(8); -- sequencial
     	vTP1tipo															varchar2(1) := '1';
     	vTP1cpf_cnpj_declarante								varchar2(14); -- vem do banco
     	vTP1nome_arquivo											varchar2(4) := 'Dirf';
     	vTP1ano_calendario										varchar2(4) := to_char(sysdate,'yyyy')-1; --mcl
     	vTP1OR																varchar2(1) := 'O';
     	vTP1sit_declaracao										varchar2(1) := '1';
     	vtipo_declarante											varchar2(1) := '2';
     	vTP1natureza_declarante								varchar2(1) := '0';
     	vTP1tipo_rendimento_imposto						varchar2(1) := '0';
     	vTP1ano_referencia										varchar2(4) := to_char(sysdate,'yyyy')-1;
     	vTP1nome_empresa_declarante						varchar2(60); -- vem do banco
     	------------------------------------------------------------------
     	-- REGISTRO TIPO 2 (INFORMAES DO BENEFICIRIOS)
     	------------------------------------------------------------------
     	vTP2info_mensais_aux									varchar2(585);
     	cTp_Dt_Detalhe												varchar2(1);
     	cDetlahe_Old													varchar2(4);
     	cAtividade_Aux												Varchar(4);
     	nAcumula_Deducao											Number;
     	nVl_Detalhamento											Number(15,2);
     	nGera_Fisica													Number(10);
     	nCont_Detalhe													Number  := 0;
     	nTotal_IR															Number  := 0;
     	nTotal_Base														Number  := 0;
     	nVl_Renda_Mes													Number  := 0;
     	bGera_Fisica                      		boolean := False;
     	bGera_Rendimento                      boolean := False;
     	bUnica_Vez   													boolean := false;
     	bUma_Vez 															boolean := False;
    	nDet_Old															dbamv.tip_detalhe.cd_detalhamento%type;
    	ctp_detalhe														dbamv.tip_detalhe.tp_detalhamento%type;
     	vTP2tipo															varchar2(1) := '2';
     	vTP2cpf_cnpj_declarante								varchar2(14); -- vem do banco
     	vTP2cod_retencao											varchar2(4); -- consultar tabela IRRF
     	vTP2identif_especie_benef							varchar2(1); -- obrigatrio - Pessoa Fsica ou Jurdica
     	vTP2cpf_cnpj_beneficiario							varchar2(14); -- vem do banco
     	vTP2nome_beneficiario									varchar2(60); -- vem do banco
      vVlRendimento													number;
     	vVlDetalhamento                       number;
     	vTP2info_mensais_benef_pf_pj					varchar2(585);
     	vTP2info_mensais_pj_pcc			          varchar2(585);
     	vTP2info_mensais_pj_pis 		          varchar2(585);
     	vTP2info_mensais_pj_cofins            varchar2(585);
     	vTP2info_mensais_pj_csll  	          varchar2(585);
     	vvl_sum_pis														number;
     	vvl_sum_cofins												number;
     	vvl_sum_csll													number;
     	vvl_sum_pis_cofins_csll								number;
     	v_cpf_cnpj														varchar2(14) :=' '; -- conferir o caso haja cnpj repetido.
     	registro2_pcc							  					varchar2(2000);
     	vTP2cod_retencao_pcc									varchar2(4); -- consultar tabela IRRF
    	type trec_info is record
       	(rendimentos			varchar2(13) := 0
       	,deducoes					varchar2(13) := 0
       	,imposto_retido		varchar2(13) := 0
       	,pis							varchar2(13) := 0
       	,cofins						varchar2(13) := 0
       	,csll		          varchar2(13) := 0
       	,pcc            	varchar2(13) := 0);
    	type ttab_info is table of trec_info
     	index by binary_integer;
     	tabT2_info_mensais										ttab_info;
    	type trec_info2 is record
       	(rendimentos			varchar2(13) := 0);
    	type ttab_info2 is table of trec_info2
     	index by binary_integer;
     	tabT2_info_mensais2										ttab_info2;
    	type tRecInfoInss is record
     	(
     		imposto_retido varchar(13):=0
     	);
    	type tTabInfoInss is table of tRecInfoInss
     	index by binary_integer;
     	tTabInfoInssMensais					tTabInfoInss;
     	vTP2identif_sit_rend_imposto					varchar2(1) := '0';
     	ncd_retencao                          varchar2(4);
     	a number;
     	contador number;
     	contador_2 number;
     	conta number;
     	------------------------------------------------------------------
     	-- VARIVEIS COMUNS
     	------------------------------------------------------------------
     	Filler					varchar2(1) := ' ';
     	Dig_Verific			varchar2(1) := '9';
     	j	 number;
     	m  number;
     	z  number;
     	FI  number := 0;
     	JU  number := 0;
     	registro_total number := 0;
     	registro_atual number := 0;
     	nome_arquivo		varchar2(50);
     	registro1				varchar2(2000);
     	registro2				varchar2(2000);
     	registro2_aux   varchar2(2000);
     	registro3				varchar2(2000);
     	vNmFornecedor   varchar2(2000);
     	bAtividade      boolean;
     	vRegistroRTRT varchar2(2000);
     	vRegistroRTIRF varchar2(2000);
      vRegistroRTPO varchar2(2000);
      auxCdAtividade number := 0;
      nr_cgc_cpf_aux varchar2(14) := '0';
      vtp_data 				dbamv.tip_detalhe.tp_data%type;
      vdt_lancamento			dbamv.con_pag.dt_lancamento%type;
      vdt_pagamento 			dbamv.itcon_pag.dt_quitacao%type;
      vcd_con_pag 				dbamv.con_pag.cd_con_pag%type;
      vcd_con_pag_filho 	dbamv.tip_detcon_pag.cd_con_pag_filho%type;
      vvl_detalhamento 	dbamv.tip_detcon_pag.vl_detalhamento%type := 0;
      vcd_atividade	 		dbamv.tip_detalhe.cd_atividade%type;
      vtp_detalhamento 	dbamv.tip_detalhe.tp_detalhamento%type;
    begin
    	-----------------------------------------------------------------
   	-- REGISTRO TIPO 2 (INFORMAES DO BENEFICIRIOS)
   	------------------------------------------------------------------
      Begin -- Fornecedores
     	  registro_total := 0;
   	    j := 1;
        for rFornecedores in cFornecedores loop
          bAtividade := true;
     		  vNmFornecedor := null;
   		    vTP2cpf_cnpj_beneficiario := null;
          open cFornecedor(rFornecedores.cd_fornecedor);
   		    fetch cFornecedor into vNmFornecedor;
   		    close cFornecedor;


          IF rFornecedores.cd_fornecedor in (04454008000189) THEN
          dbamv.prc_grava_log_erro('PALOMA','','','forn = '||vNmFornecedor,1); --pmva
          END IF;

   		    vTP2nome_beneficiario	:= substr(vNmFornecedor, 1, 60);
   		    If rFornecedores.tp_fornecedor = 'F' Then
   		      vTP2identif_especie_benef	:= '1';
   		    Else
   		      vTP2identif_especie_benef	:= '2';
   		    End if;
   		    vTP2cpf_cnpj_beneficiario := rFornecedores.nr_cgc_cpf;
   		    vVlRendimento := 0;
        	-- Limpando as Variceis de tabela
   		    for k in 1..13 loop
   			    tabT2_info_mensais(k).rendimentos 		  := 0;
   		 	    tabT2_info_mensais(k).deducoes 		  	:= 0;
            tabT2_info_mensais2(k).rendimentos 		:= 0;
   			  end loop;
          -- Carregando os rendimento
   		    vVlRendimento	:= 0;

   		    for rVlRendimento in cVlRendimento(rFornecedores.cd_fornecedor, rFornecedores.tp_fornecedor ) LOOP

   		  	  j := rVlRendimento.dt_base;
   			    tabT2_info_mensais(j).rendimentos	:= nvl(tabT2_info_mensais(j).rendimentos,0) + nvl(rVlRendimento.vl_rendimento,0);
   			    vVlRendimento 	:= 	vVlRendimento + nvl(rVlRendimento.vl_rendimento,0);
   			    tabT2_info_mensais2(J).rendimentos := nvl(tabT2_info_mensais2(j).rendimentos,0) + nvl(rVlRendimento.vl_rendimento,0);

              IF rFornecedores.cd_fornecedor in (04454008000189) THEN
                dbamv.prc_grava_log_erro('PALOMA','','','Vl_Rendimento = '||vVlRendimento,1); --pmva
              END IF;

   		    End loop;
   		    nTotal_IR := 0;
   		    open Busca_IR( rFornecedores.cd_fornecedor );
   		    fetch Busca_IR into nTotal_IR;
   		    close Busca_IR;

          IF rFornecedores.cd_fornecedor in (04454008000189) THEN
             dbamv.prc_grava_log_erro('PALOMA','','','IR = '||nTotal_IR,3); --pmva
          END IF;

   		    nGera_Fisica := 0;
   		    cDetlahe_Old := 'XXXX';
   		    If vVlRendimento >= 6000 then
   			    bUnica_Vez   := true;
   		    else
   		   	  bUnica_Vez   := false;
   		    end if;
   		    Begin -- Begin da Atividade
            If vVlRendimento >= 0 then
   		 		    vRegistroRTRT := NULL;
   				    vRegistroRTIRF := NULL;
   				    vRegistroRTPO  := NULL;
   		  	    For nAtividade in cBusca_Atividade loop
   	  			    bGera_Rendimento := false;
   	  			    bGera_Fisica     := false;
                Open cDetalhamento_Cont( rFornecedores.cd_fornecedor, nAtividade.Cd_Atividade );
   	  			    Fetch cDetalhamento_Cont Into nCont_Detalhe;
   	  			    Close cDetalhamento_Cont;

           IF rFornecedores.cd_fornecedor in (04454008000189) THEN
            dbamv.prc_grava_log_erro('PALOMA','','','Count Detalhe: '||nCont_Detalhe||'-'||' Ativ: '|| nAtividade.Cd_Atividade||' Forn: '||rFornecedores.cd_fornecedor,4); --pmva
          END IF;
   	  			    -- Preenchimento das 13 posies do vetor.
   	  			    for k in 1..13 loop
   	  				    tabT2_info_mensais(k).deducoes 		  		:= 0;
   		  			    tabT2_info_mensais(k).imposto_retido		:= 0;
   		  			    tTabInfoInssMensais(k).imposto_retido := 0;
   	  			    end loop;
                ctp_detalhe := null;
   					    If nvl(nCont_Detalhe,0) > 0 Then
   						    bUma_Vez    		:= True;
   						    nDet_Old				:= null;
   						    nTotal_Base 		:= 0;
   						    vVlDetalhamento := 0;

    					    for rVlDetalhamento in cDetalhamento( rFornecedores.cd_fornecedor, nAtividade.Cd_Atividade ) LOOP

                   IF rFornecedores.cd_fornecedor in (04454008000189) THEN
                          dbamv.prc_grava_log_erro('PALOMA','','','Data Pgto: '||rVlDetalhamento.dt_pagamento||' conta: '||rVlDetalhamento.cd_con_pag,1);--pmva
                    END IF;


    					  		If trunc(rVlDetalhamento.dt_pagamento) between trunc(pDtInicial) and trunc(pDtFinal) THEN

   										j := to_char(rVlDetalhamento.Dt_pagamento,'mm');
   										tabT2_info_mensais(j).imposto_retido	:= nvl(tabT2_info_mensais(j).imposto_retido,0) + nvl(rVlDetalhamento.vl_detalhamento,0);
   		            	  vVlDetalhamento 	:= 	vVlDetalhamento  + nvl(rVlDetalhamento.vl_detalhamento     ,0);
   										nTotal_Base := tabT2_info_mensais(j).rendimentos;

                       IF rFornecedores.cd_fornecedor in (04454008000189) THEN
                          dbamv.prc_grava_log_erro('PALOMA','','','cDet: '||nCont_Detalhe||'-'||' Ativ: '|| nAtividade.Cd_Atividade||' Forn: '||rFornecedores.cd_fornecedor||'Valor Det: '||vVlDetalhamento,4); --pmva
                       END IF;

   								  End If;
   			            bGera_Fisica      := true;
   		              bUnica_Vez        := false;
   		              if rVlDetalhamento.tp_detalhamento <> 'X' then
   		                ctp_detalhe	:= rVlDetalhamento.tp_detalhamento;
   		              end if;
    					    end loop; --- loop do detalhe
    						  /*Monta a deduo do inss*/
   						    for rVlDetalhamento in cDetalhamentoInss( rFornecedores.cd_fornecedor ) loop
   							    if to_char(rVlDetalhamento.dt_pagamento,'mm') is not null then
   									  j := to_char(rVlDetalhamento.dt_pagamento,'mm');
   									  tTabInfoInssMensais(j).imposto_retido := nvl(tTabInfoInssMensais(j).imposto_retido,0) + nvl(rVlDetalhamento.vl_detalhamento,0);
									  vVlDetalhamento 	:= 	vVlDetalhamento  + nvl(rVlDetalhamento.vl_detalhamento     ,0);

   							    end if;
   						    end loop;
    					    if ctp_detalhe is null then
    					       ctp_detalhe := 'X';
    					    end if;
   						    if  ( ( nvl(nTotal_IR,0) >= 0 or vVlRendimento > 0 ) and vVlDetalhamento >= 0 ) and  rFornecedores.tp_fornecedor = 'F' then
   							    registro2_aux := null;
   							    vRegistroRTRT := 'RTRT|';
   					  	    vRegistroRTIRF := 'RTIRF|';
   							    vRegistroRTPO := 'RTPO|';
   							    for k in 1..13 loop
   								    IF nvl(tabT2_info_mensais(k).rendimentos,0 ) <> 0 THEn
   									    vRegistroRTRT := vRegistroRTRT||lPad( Replace( Replace( TO_CHAR( TO_NUMBER( nvl(tabT2_info_mensais(k).rendimentos   ,0 ) ), 'fm99g999g999g990d00' ), '.','' ), ',','' ), 13, '0' )||'|';
   								    Else
   									    vRegistroRTRT := vRegistroRTRT||'|';
   								    END IF;
   								    if nvl(tTabInfoInssMensais(k).imposto_retido,0) <> 0 then
   									    vRegistroRTPO := vRegistroRTPO||lPad( Replace( Replace( TO_CHAR( TO_NUMBER( nvl(tTabInfoInssMensais(k).imposto_retido   ,0 ) ), 'fm99g999g999g990d00' ), '.','' ), ',','' ), 13, '0' )||'|';
   								    else
   									    vRegistroRTPO := vRegistroRTPO||'|';
   								    end if;
   								    If ctp_detalhe <> 'N' then
   									    if nvl(tabT2_info_mensais(k).imposto_retido,0 ) <> 0 then
   										    vRegistroRTIRF := vRegistroRTIRF || lPad( Replace( Replace( TO_CHAR( TO_NUMBER( nvl(tabT2_info_mensais(k).imposto_retido,0 ) ), 'fm99g999g999g990d00' ), '.','' ), ',','' ), 13, '0' ) ||'|';
   									    else
   										    vRegistroRTIRF := vRegistroRTIRF||'|';
   									    end if;
   								    Else
   								       vRegistroRTIRF := vRegistroRTIRF||'|';
   								    End if;
   								    If ctp_detalhe <> 'N' Then
   									    bGera_Fisica := true;
   								    End If;
   							    end loop;
   							    if bAtividade then
   								    insert into DBAMV.TMPMV_FNFI_GERACAO_DIRF values (sysdate, vTP2cpf_cnpj_beneficiario, nAtividade.cd_atividade, vRegistroRTRT, 'F',vVlRendimento, vRegistroRTIRF,vTP2nome_beneficiario, vRegistroRTPO);
   							    End if;
   							    bAtividade := false;
   							    vTP2info_mensais_benef_pf_pj 	:= null;
   							    vTP2info_mensais_aux					:= null;
   							  Elsif vVlRendimento > 0 and vVlDetalhamento >= 0 and  rFornecedores.tp_fornecedor = 'J' THEN

                    IF rFornecedores.cd_fornecedor in (04454008000189) THEN
                       dbamv.prc_grava_log_erro('PALOMA','','','Imposto PJ '|| vVlDetalhamento||'-'||vVlRendimento,5); --pmva
                    END IF;

   								  If ctp_detalhe <> 'N' Then
   									  vRegistroRTRT := 'RTRT|';
   							  	  vRegistroRTIRF := 'RTIRF|';


   	 					  		  for k in 1..13 loop
   										  IF nvl(tabT2_info_mensais(k).rendimentos   ,0 ) <> 0 then
   											  vRegistroRTRT := vRegistroRTRT|| lPad( Replace( Replace( TO_CHAR( TO_NUMBER( nvl(tabT2_info_mensais(k).rendimentos,0 ) ), 'fm99g999g999g990d00' ), '.','' ), ',','' ), 13, '0' )||'|';


   										  else
   											  vRegistroRTRT := vRegistroRTRT||'|';



   										  end if;
   										  if nvl(tabT2_info_mensais(k).imposto_retido,0 ) <> 0 then
   											  vRegistroRTIRF := vRegistroRTIRF || lPad( Replace( Replace( TO_CHAR( TO_NUMBER( nvl(tabT2_info_mensais(k).imposto_retido,0 ) ), 'fm99g999g999g990d00' ), '.','' ), ',','' ), 13, '0' )||'|';


   										  else
   											  vRegistroRTIRF := vRegistroRTIRF||'|';


   										  end if;
   	 					  		  end loop;



   	            		  insert into DBAMV.TMPMV_FNFI_GERACAO_DIRF values (sysdate, vTP2cpf_cnpj_beneficiario, nAtividade.cd_atividade, vRegistroRTRT, 'J',vVlRendimento, vRegistroRTIRF, vTP2nome_beneficiario, vRegistroRTPO);
   	            		  vTP2info_mensais_benef_pf_pj := null;
   	            	  End if;
   						    End if;

   					    Elsif nCont_Detalhe = 0 THEN

   						    if vVlRendimento >= 6000 and rFornecedores.tp_fornecedor = 'F' and bUnica_Vez	= TRUE AND nAtividade.cd_atividade = '0588'  THEN
                    vRegistroRTRT := 'RTRT|';
   					  	    vRegistroRTIRF := 'RTIRF|';
                    vRegistroRTPO := 'RTPO|';
   							    bUnica_Vez := False;

                    --Monta a deduo do inss
   						      for rVlDetalhamento in cDetalhamentoInss( rFornecedores.cd_fornecedor ) loop
   							      if to_char(rVlDetalhamento.dt_pagamento,'mm') is not null then
   									    j := to_char(rVlDetalhamento.dt_pagamento,'mm');
   									    tTabInfoInssMensais(j).imposto_retido := nvl(tTabInfoInssMensais(j).imposto_retido,0) + nvl(rVlDetalhamento.vl_detalhamento,0);
   							      end if;
   						      end loop;

   							    for k in 1..13 loop
   								    IF nvl(tabT2_info_mensais(k).rendimentos   ,0 ) <> 0 THEn
   									    vRegistroRTRT := vRegistroRTRT||lPad( Replace( Replace( TO_CHAR( TO_NUMBER( nvl(tabT2_info_mensais(k).rendimentos   ,0 ) ), 'fm99g999g999g990d00' ), '.','' ), ',','' ), 13, '0' )||'|';
   								    Else
   									    vRegistroRTRT := vRegistroRTRT||'|';
   								    END IF;
   								    If ctp_detalhe <> 'N' then
   									    if nvl(tabT2_info_mensais(k).imposto_retido,0 ) <> 0 then
   										    vRegistroRTIRF := vRegistroRTIRF || lPad( Replace( Replace( TO_CHAR( TO_NUMBER( nvl(tabT2_info_mensais(k).imposto_retido,0 ) ), 'fm99g999g999g990d00' ), '.','' ), ',','' ), 13, '0' ) ||'|';
   									    else
   										    vRegistroRTIRF := vRegistroRTIRF||'|';
   									    end if;
   								    Else
   									    vRegistroRTIRF := vRegistroRTIRF||'|';
   								    End if;
   								    registro2_aux := null;
   								    If Nvl(ctp_detalhe,'X') <> 'N' Then
   									    bGera_Fisica := true;
   								    End If;

                      --S ir inserir o INSS se houver reteno para o fornecedor
									    bGera_Rendimento := true;
                      if nvl(tTabInfoInssMensais(k).imposto_retido,0) <> 0 then
   									    vRegistroRTPO := vRegistroRTPO||lPad( Replace( Replace( TO_CHAR( TO_NUMBER( nvl(tTabInfoInssMensais(k).imposto_retido   ,0 ) ), 'fm99g999g999g990d00' ), '.','' ), ',','' ), 13, '0' )||'|';
   								    else
   									    vRegistroRTPO := vRegistroRTPO||'|';
   								    end if;
   							    end loop; --for k in 1..13 loop
   							    if bGera_Fisica and cDetlahe_Old <> nAtividade.cd_atividade then
   								    nGera_Fisica := nGera_Fisica + 1;
   								    cDetlahe_Old := nAtividade.cd_atividade;
   						        insert into DBAMV.TMPMV_FNFI_GERACAO_DIRF values (sysdate, vTP2cpf_cnpj_beneficiario, nAtividade.cd_atividade, vRegistroRTRT, 'F',vVlRendimento, vRegistroRTIRF, vTP2nome_beneficiario, vRegistroRTPO);
   							    End If;
   							    If bGera_Rendimento then
   								    if bGera_Fisica = false and nGera_Fisica = 0 then
   									    insert into DBAMV.TMPMV_FNFI_GERACAO_DIRF values (sysdate, vTP2cpf_cnpj_beneficiario, nAtividade.cd_atividade, vRegistroRTRT, 'F',vVlRendimento, vRegistroRTIRF, rpad(vTP2nome_beneficiario,60,' '), vRegistroRTPO);
   									  end if;
   								  End if;
   							  End If; --if vVlRendimento >= 6000 and rFornecedores.tp_fornecedor = 'F' and bUnica_Vez	= TRUE AND nAtividade.cd_atividade = '0588'  THEN
   							  vTP2info_mensais_benef_pf_pj 	:= null;
   							  vTP2info_mensais_aux					:= null;
   						  End if; --If nvl(nCont_Detalhe,0) > 0 Then
   					    vRegistroRTRT := NULL;
   			  	    vRegistroRTIRF := NULL;
   					    vRegistroRTPO  := NULL;
   		        End loop; -- Loop da Atividade
            End if; -- Redimentos > que zero
   		    Exception
   		  	  When Others Then
   		  	     Raise_Application_Error(-20999,'Erro 002: Registro Tipo 2 Detalhamento. Arquivo NO foi gerado! '|| sqlerrm);
   	      End; -- Begin da Atividade
   	    End Loop; -- Loop dos Fornecedores
        COMMIT;
      END;
    end prc_dirf_pagamento;

   end pkg_fnfi_dirf;
/

GRANT EXECUTE ON dbamv.pkg_fnfi_dirf TO dbaportal;
GRANT EXECUTE ON dbamv.pkg_fnfi_dirf TO dbaps;
GRANT EXECUTE ON dbamv.pkg_fnfi_dirf TO dbasgu;
GRANT EXECUTE ON dbamv.pkg_fnfi_dirf TO mv2000;
GRANT EXECUTE ON dbamv.pkg_fnfi_dirf TO mvintegra;
