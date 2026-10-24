"""Small original fixtures for wide, rich-text, multi-input and saved-result imports."""
from pathlib import Path
import csv
import io
import json
import zipfile

root=Path(__file__).resolve().parent/'fixtures'
root.mkdir(exist_ok=True)
for full in [False,True]:
    files={}
    def put(path,value):files[path]=json.dumps(value)
    def table(sid,kind,data_format,datasets,rows,nrep=None,derived=False,exclusions=False):
        tid=sid+'_TABLE';ids=[sid+'_Y'+str(i) for i in range(len(datasets))]
        table={'@class':'XYDataTable' if kind=='xy' else 'DataTable','uid':tid,'format':'view' if derived else kind,'dataFormat':data_format,'dataSets':ids}
        if nrep is not None:table['replicatesCount']=nrep
        if kind=='xy':table['xDataSet']=sid+'_X';table['xDataSetFormat']='y_single'
        # EXCLUDED in future-column formatting does not describe the actual cells.
        if sid=='WIDE':table['columnFormats']=[{'start':1,'count':2047,'replicates':[{'start':0,'count':50,'format':{'attributes':['EXCLUDED']}}]}]
        put(f'data/sheets/{sid}/sheet.json',{'uid':sid,'title':sid,'table':table})
        put(f'data/tables/{tid}/content.json',{'numberOfRows':len(rows),'numberOfColumns':len(rows[0])})
        stream=io.StringIO();csv.writer(stream).writerows(rows);files[f'data/tables/{tid}/data.csv']=stream.getvalue()
        for uid,title in zip(ids,datasets):put(f'data/sets/{uid}.json',{'title':{'string':title,'formatting':[]},'attributes':['EXCLUDED'] if exclusions else ['DS_ATTR_Y']})
        return ids
    wide=[[r]+[(100*r+j if full or j<=2 else '') for j in range(1,51)] for r in range(2)]
    table('WIDE','xy','y_replicates',['Signal'],wide,nrep=50)
    student=table('STUDENT','column','y_single',['Control','Treatment'],[[1,3],[3,6],[4,8],[6,10]])
    table('SUMMARY','xy','y_se',['Response'],[[0,2,.5],[1,4,.8]])
    table('EXCLUSIONS','xy','y_single',['Unreviewed'],[[0,4],[1,9]],exclusions=True)
    table('GROUPED','grouped','y_replicates',['A','B'],[[j for j in range(1,101)]],nrep=50)
    table('SAVED','xy','y_se',['Normalized'],[[0,1,.1],[1,2,.2]],derived=True)
    put('analyses/MULTI/sheet.json',{'uid':'MULTI','title':'Multiple source calculation','analysisClass':'REMOVE_BASELINE','inputSheets':[{'uid':'WIDE'},{'uid':'STUDENT'}],'resultSheets':[{'uid':'OUT'}]})
    put('analyses/MULTI/result_sheets/OUT.json',{'dataSheet':'SAVED'})
    put('analyses/TEST/sheet.json',{'uid':'TEST','title':'Unpaired test','analysisClass':'T_TESTS_AND_NONPARAMETRIC','isAllDataAnalyzed':True,'inputSheets':[{'uid':'STUDENT'}],'inputDataSets':[{'uid':x} for x in student]})
    put('analyses/TEST/parameters.json',{'$id':'analyses/two_sample_tests/parameters.schema.json','version':'0.0.0','content':{'experimentalDesign':'UNPAIRED_T_TEST','options':{'swapDirection':True,'pValueTailType':'P_VALUE_TWO_TAILED','significanceLevel':.05}}})
    put('analyses/ORPHAN/sheet.json',{'uid':'ORPHAN','title':'Unlinked calculation','analysisClass':'REMOVE_BASELINE','inputSheets':[]})
    put('document.json',{'sheets':{'data':['WIDE','STUDENT','SUMMARY','EXCLUSIONS','GROUPED'],'analyses':['MULTI','TEST','ORPHAN'],'graphs':[]}})
    target=root/('fully-populated-replicates.prism' if full else 'multi-input-workbook.prism')
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as z:
        for name,value in files.items():z.writestr(name,value)
