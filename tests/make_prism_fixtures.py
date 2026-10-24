"""Original synthetic data; no GraphPad samples are redistributed."""
from pathlib import Path
import json, zipfile, xml.etree.ElementTree as E
import runpy
runpy.run_path(str(Path(__file__).with_name('make_compatibility_fixture.py')))
root=Path(__file__).resolve().parent/'fixtures'
root.mkdir(exist_ok=True)
xml=E.Element('GraphPadPrismFile',PrismXMLVersion='5.00')
def column(parent,tag,name,values):
    c=E.SubElement(parent,tag);E.SubElement(c,'Title').text=name
    for series in values:
        s=E.SubElement(c,'Subcolumn')
        for value in series:
            d=E.SubElement(s,'d')
            if value=='excluded': d.set('Excluded','1');d.text='999'
            elif value is not None: d.text=str(value)
    return c
t=E.SubElement(xml,'Table',ID='OriginalXY',TableType='XY',XFormat='numbers',YFormat='replicates')
E.SubElement(t,'Title').text='Original XY & triplicates'
column(t,'XColumn','Time',[[0,1,2,3]])
column(t,'YColumn','Control',[[1,2,3,4],[2,3,None,5],[3,4,'excluded',6]])
column(t,'YColumn','Drug',[[2,4,6,8],[3,5,7,9],[4,6,8,10]])
t=E.SubElement(xml,'Table',ID='OriginalColumn',TableType='OneWay',XFormat='none',YFormat='replicates')
E.SubElement(t,'Title').text='Original groups'
column(t,'YColumn','A',[[1,2,3]]);column(t,'YColumn','B',[[4,5,6]])
t=E.SubElement(xml,'Table',ID='Unsupported',TableType='XY',XFormat='numbers',YFormat='SD')
E.SubElement(t,'Title').text='Summary values'
E.ElementTree(xml).write(root/'source-tables.pzfx',encoding='utf-8',xml_declaration=True)
files={'document.json':json.dumps({'sheets':{'data':['XY','GROUPED','SUMMARY']}})}
def table(sid,kind,names,nrep,csv,rows,lead=True,summary=False):
    tid='T_'+sid
    meta={'title':'Original '+sid,'table':{'uid':tid,'format':kind,'dataFormat':'y_sd_n' if summary else 'y_replicates','replicatesCount':nrep,'dataSets':[]}}
    if lead: meta['table']['xDataSet' if kind=='xy' else 'rowTitlesDataSet']='LABEL_'+sid
    for i,name in enumerate(names):
        ds='S_'+sid+'_'+str(i);meta['table']['dataSets'].append(ds)
        files['data/sets/'+ds+'.json']=json.dumps({'uid':ds,'title':name})
    files['data/sheets/'+sid+'/sheet.json']=json.dumps(meta)
    files['data/tables/'+tid+'/content.json']=json.dumps({'numberOfRows':rows,'numberOfColumns':len(names)*nrep+int(lead)})
    files['data/tables/'+tid+'/data.csv']=csv
table('XY','xy',['Excluded group','Drug'],2,'0,1,2,3,4\n1,2,3,4,5\n2,3,4,5,6\n',3)
table('GROUPED','grouped',['Vehicle','Drug'],2,'Day 1,1,2,3,4\nDay 2,3,4,5,6\n',2)
table('SUMMARY','xy',['Mean'],3,'0,2,1,3\n1,3,1,3\n',2,summary=True)
doc=json.loads(files['document.json']);doc['sheets']['graphs']=['RAW_SOURCE_GRAPH'];files['document.json']=json.dumps(doc)
files['graphs/RAW_SOURCE_GRAPH/sheet.json']=json.dumps({'@class':'FENGraphSheet','uid':'RAW_SOURCE_GRAPH','title':'Original XY source graph','inputDataSets':['S_XY_0','S_XY_1']})
with zipfile.ZipFile(root/'source-tables.prism','w',zipfile.ZIP_DEFLATED) as z:
    for name,text in files.items():z.writestr(name,text)
with zipfile.ZipFile(root/'unsafe-source.prism','w') as z:z.writestr('../outside.txt','not extracted')
(root/'unsafe-source.pzfx').write_text('<!DOCTYPE x [<!ENTITY x SYSTEM "file:///private/tmp/never-read">]><GraphPadPrismFile>&x;</GraphPadPrismFile>')
(root/'cdata-source.pzfx').write_text('<GraphPadPrismFile><Table TableType="OneWay" YFormat="replicates"><Title><![CDATA[CDATA & labels]]></Title><YColumn><Title><![CDATA[Control & alpha]]></Title><Subcolumn><d><![CDATA[1]]></d><d>2</d><d>3</d></Subcolumn></YColumn></Table></GraphPadPrismFile>')
print('Created original Prism import fixtures')

# Synthetic examples of the public JSON structures observed in Prism 11 templates.
files={}
source_id='MV';datasets=['SUBJECT','GROUP','RESPONSE','TIME']
meta={'@class':'DataSheet','uid':source_id,'title':'Original matched experiment','table':{'uid':'MV_TABLE','format':'multivariable','dataFormat':'y_single','dataSets':datasets}}
files['data/sheets/MV/sheet.json']=json.dumps(meta)
for uid,title,kind in zip(datasets,['Subject','Group','Response','Time'],['categorical','categorical','continuous','continuous']):
    files['data/sets/'+uid+'.json']=json.dumps({'@class':'VariableDataSet','uid':uid,'title':title,'currentType':kind,'attributes':['DS_ATTR_Y']})
rows=[['S1','Control',5,0],['S2','Drug',8,1],['S2','Control',6,1],['S1','Drug',9,0],['S3','Control',7,2],['S3','Drug',10,2],['S4','Control',9,3],['S4','Drug',13,3],['S5','Control',10,4],['S5','Drug',15,4]]
files['data/tables/MV_TABLE/data.csv']='\n'.join(','.join(map(str,row)) for row in rows)+'\n'
files['data/tables/MV_TABLE/content.json']=json.dumps({'numberOfRows':len(rows),'numberOfColumns':4,'version':1})
def ref(uid,index,title):return {'col':{'uid':uid,'idx':index,'title':title}}
paired={'analysisClass':'T_TESTS_AND_NONPARAMETRIC','content':{'experimentalDesign':'PAIRED_T_TEST','variableDesign':{'responseList':[ref('RESPONSE',2,'Response')],'factorList':[ref('GROUP',1,'Group')],'subject':ref('SUBJECT',0,'Subject')},'options':{'swapDirection':True,'pValueTailType':'P_VALUE_TWO_TAILED','significanceLevel':0.05}}}
pca={'analysisClass':'PCA','content':{'data':{'variables':[ref('RESPONSE',2,'Response'),ref('TIME',3,'Time')]},'calc':{'transform':'STANDARDIZE_DATA','method':'PARALLEL_ANALYSIS','componentCount':2,'regression':{'run':False}},'graph':{'variables':{'symbolColor':{'use':True,'variable':ref('GROUP',1,'Group')}}}}}
for aid,p,title in [('PAIRED',paired,'Matched response'),('PCA',pca,'Response and time PCA')]:
    files[f'analyses/{aid}/sheet.json']=json.dumps({'@class':'AnalysisSheet','uid':aid,'title':title,'analysisClass':p['analysisClass'],'isAllDataAnalyzed':True,'inputSheets':[{'uid':'MV','title':meta['title']}]})
    files[f'analyses/{aid}/parameters.json']=json.dumps(p)
files['analyses/BINARY/sheet.json']=json.dumps({'uid':'BINARY','title':'Legacy binary fit','analysisClass':'LINEAR_REGRESSION','isAllDataAnalyzed':True,'inputSheets':[{'uid':'MV'}]})
files['analyses/BINARY/parameters.dt']='opaque binary parameters are never evaluated'
axis=lambda lo,hi:{'segments':[{'@class':'LinearAxisSegment','isLowerLimitFixed':True,'isUpperLimitFixed':True,'lowerLimit':lo,'upperLimit':hi}], 'title':{'text':{'string':'Time' if hi==5 else 'Response'}}}
graph={'@class':'GraphSheet','uid':'XY_GRAPH','title':'Editable response graph','graph':{'@class':'MVGraph','dataSheet':'MV','xVariables':['TIME'],'yVariables':['RESPONSE'],'gdoTypes':{'defaults':['symbols']},'gdoSettings':{'symbols':{}},'title':{'text':{'string':'Response by time'}},'axisX':axis(0,5),'axisY':axis(0,20)}}
files['graphs/XY_GRAPH/sheet.json']=json.dumps(graph)
files['graphs/BINARY_GRAPH/sheet.json']=json.dumps({'@class':'FENGraphSheet','uid':'BINARY_GRAPH','title':'Legacy decorated graph','inputDataSets':['RESPONSE']})
files['document.json']=json.dumps({'sheets':{'data':['MV'],'analyses':['PAIRED','PCA','BINARY'],'graphs':['XY_GRAPH','BINARY_GRAPH']}})
with zipfile.ZipFile(root/'editable-workflows.prism','w',zipfile.ZIP_DEFLATED) as z:
    for name,text in files.items():z.writestr(name,text)
